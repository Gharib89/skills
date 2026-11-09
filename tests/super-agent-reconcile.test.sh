#!/usr/bin/env bash
# super-agent's `reconcile`, driven through its command line over fake `t3` and
# `gh` on PATH (tests/super-agent-fake.sh): it compares the ledger with T3 and
# GitHub, marks merged and closed entries, records the baseline `watch` reads,
# and reports one JSON summary.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=Gharib89/skills
R() { bash "$s/reconcile.sh" --ledger "$led" "$@"; }
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
calls() { cat "$SA_FAKE/calls" 2>/dev/null; }
stage() { jq -r --arg k "$repo#$1" '.entries[$k].stage' "$led"; }

# fixture: tickets 5 and 6, just launched, each with a running thread, no PR and
# an open issue
fixture() {
  rm -f "$led" "$SA_FAKE/calls"
  for n in 5 6; do
    L add --repo $repo --number $n --thread "t-$n" --worktree "/wt/$n" --branch "feat/x-$n" >/dev/null
    sa_thread "t-$n" running 1 0 "/wt/$n" "feat/x-$n"
    sa_pr $repo "feat/x-$n" none
    sa_issue $repo "$n" open
  done
}

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/reconcile.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: reconcile" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/reconcile.sh" --nope 2>/dev/null); rc=$?
check "a malformed call answers its usage line" "$(sed -n 1p <<<"$(bash "$s/reconcile.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a malformed call exits 2" 2 "$rc"

# --- a launched entry gets its baseline ----------------------------------------
fixture
out=$(R); rc=$?
check_rc "reconcile exits 0" 0 "$rc"
check "one JSON object is the whole answer" 1 "$(jq -s length <<<"$out")"
check "it checked both entries" 2 "$(jq .checked <<<"$out")"
check "a running thread moves its entry from launched to running" "launched>running launched>running" \
  "$(jq -r '[.entries[] | "\(.from)>\(.stage)"] | join(" ")' <<<"$out")"
check "the baseline is in the ledger" '{"status":"running","run_count":1,"pending":0,"gate":false,"pr":{"number":null,"state":"none"}}' \
  "$(jq -c --arg k "$repo#5" '.entries[$k].observed' "$led")"
check "so a watch after it sees nothing" "null timeout" \
  "$(bash "$s/watch.sh" --ledger "$led" --interval 1 --timeout 2 | jq -r '[(.key // "null"), .event] | join(" ")')"

# --- a run at rest with its PR open --------------------------------------------
fixture
sa_thread t-5 idle 3 0 /wt/5 feat/x-5
sa_pr $repo feat/x-5 open
out=$(R)
check "a run at rest with the ticket undone is at-rest" at-rest "$(stage 5)"
check "and is listed for the super agent to judge" "$repo#5" "$(jq -r '.at_rest[].key' <<<"$out")"
check "the ledger holds the PR it found" '{"number":7,"state":"open"}' "$(jq -c --arg k "$repo#5" '.entries[$k].observed.pr' "$led")"
check "the ticket still running stays running" running "$(stage 6)"
check "nothing is settled or closed" "[[],[]]" "$(jq -c '[.settled, .closed]' <<<"$out")"

# --- a merged PR settles its entry ---------------------------------------------
fixture
sa_pr $repo feat/x-5 merged
sa_thread t-5 idle 2 0 /wt/5 feat/x-5
out=$(R)
check "a merged PR marks its entry settled" settled "$(stage 5)"
check "and names the thread and worktree to settle" "$repo#5 t-5 /wt/5" \
  "$(jq -r '.settled[] | "\(.key) \(.thread) \(.worktree)"' <<<"$out")"
check "the other entry is untouched by it" running "$(stage 6)"
: > "$SA_FAKE/calls"
out=$(R)
check "a settled entry is not checked again" 1 "$(jq .checked <<<"$out")"
check "t3 was not asked about it" "" "$(calls | grep '^t3 thread show t-5 ')"
check "and it is not settled twice" "[]" "$(jq -c .settled <<<"$out")"

# --- a PR closed unmerged, an issue closed -------------------------------------
fixture
sa_pr $repo feat/x-5 closed
out=$(R)
check "a PR closed unmerged marks its entry closed" closed "$(stage 5)"
check "and says why" "$repo#5 pr-closed" "$(jq -r '.closed[] | "\(.key) \(.reason)"' <<<"$out")"
fixture
sa_issue $repo 6 closed
out=$(R)
check "an issue closed with no PR marks its entry closed" closed "$(stage 6)"
check "and says why" "$repo#6 issue-closed" "$(jq -r '.closed[] | "\(.key) \(.reason)"' <<<"$out")"
fixture
sa_pr $repo feat/x-5 merged
sa_thread t-5 idle 2 0 /wt/5 feat/x-5
sa_issue $repo 5 closed
R >/dev/null
check "a merged PR outranks the issue it closed" settled "$(stage 5)"

# --- what it cannot read is reported and leaves its entry alone ----------------
fixture
before=$(jq -c --arg k "$repo#5" '.entries[$k]' "$led")
rm "$SA_FAKE/threads/t-5.json"
out=$(R); rc=$?
check_rc "an unreadable thread does not fail the run" 0 "$rc"
check "it is in errors with its kind" "$repo#5 thread-unreadable" "$(jq -r '.errors[] | "\(.key) \(.kind)"' <<<"$out")"
check "its entry is as it was, but for the error it carries" "$before" \
  "$(jq -c --arg k "$repo#5" '.entries[$k] | del(.error)' "$led")"
check "the error is the kind" thread-unreadable "$(jq -r --arg k "$repo#5" '.entries[$k].error' "$led")"
sa_thread t-5 running 1 0 /wt/5 feat/x-5
R >/dev/null
check "a good read clears the error" null "$(jq -c --arg k "$repo#5" '.entries[$k].error' "$led")"
check "the other entry is still reconciled" running "$(stage 6)"
fixture
rm "$SA_FAKE/gh/"*issues_5
check "an issue GitHub will not answer is issue-unreadable" "$repo#5 issue-unreadable" "$(R | jq -r '.errors[] | "\(.key) \(.kind)"')"
fixture
sa_thread t-5 running 1 0 /elsewhere feat/x-5
check "a thread of that id elsewhere is thread-mismatch" "$repo#5 thread-mismatch" "$(R | jq -r '.errors[] | "\(.key) \(.kind)"')"

# --- the stall count -----------------------------------------------------------
stalls() { jq -r --arg k "$repo#$1" '.entries[$k].stalls' "$led"; }
stalled() { jq -r '[.stalled[] | "\(.key) \(.stalls) \(.reason)"] | join(",")' <<<"$1"; }
old=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)
fixture
R >/dev/null
check "a first look is a baseline, never a stall" 0 "$(stalls 5)"
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "Stopped after the tests."
out=$(R)
check "a completed run with no PR and no gate summary is a stall" "$repo#5 1 run-completed" "$(stalled "$out")"
check "which raises the count" 1 "$(stalls 5)"
check "and the other ticket, still running, is not one" 0 "$(stalls 6)"
check "the entries list carries the count" 1 "$(jq '[.entries[] | select(.key == "'"$repo#5"'")][0].stalls' <<<"$out")"
out=$(R)
check "the same run seen again is not a second stall" "" "$(stalled "$out")"
check "its count stays" 1 "$(stalls 5)"
L set "$repo#5" rest_since "\"$old\"" >/dev/null
out=$(R --stall-window 60)
check "a thread at rest past the window, with no new run, is another stall" "$repo#5 2 stall-window" "$(stalled "$out")"
out=$(R --stall-window 60)
check "and the window starts over from that count" "" "$(stalled "$out")"
sa_thread t-5 running 2 0 /wt/5 feat/x-5
R >/dev/null
check "a new run is no stall and no step" 2 "$(stalls 5)"
sa_thread t-5 idle 2 0 /wt/5 feat/x-5 "ship 0.54.2: the merge gate is clean. Unmet criteria: none."
out=$(R)
check "a run that ends in the merge-gate summary is a real step: the count falls" 1 "$(stalls 5)"
check "and is no stall" "" "$(stalled "$out")"
sa_thread t-5 running 3 0 /wt/5 feat/x-5
sa_pr $repo feat/x-5 open
R >/dev/null
check "a PR opened since the last look is a real step too" 0 "$(stalls 5)"
sa_thread t-5 idle 3 0 /wt/5 feat/x-5 "ship 0.54.2: the merge gate is clean. Unmet criteria: none."
R >/dev/null
check "the count floors at 0" 0 "$(stalls 5)"
sa_thread t-5 idle 4 1 /wt/5 feat/x-5 "Stopped after the tests."
out=$(R)
check "a thread holding a permission request is no stall" "" "$(stalled "$out")"
fixture
R >/dev/null
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "Stopped after the tests."
L set "$repo#5" stalls 3 >/dev/null
L set "$repo#5" rest_since "\"$old\"" >/dev/null
out=$(R --stall-window 60)
check "an entry already at 3 stalls is escalated: no stall past 3 for its window" "" "$(stalled "$out")"
check "and its count stays 3" 3 "$(stalls 5)"
sa_thread t-5 idle 2 0 /wt/5 feat/x-5 "Stopped again."
check "nor for a new completed run" "" "$(stalled "$(R --stall-window 60)")"
L set "$repo#5" stalls 0 >/dev/null
check "after the owner's reset a thread still at rest past its window counts again" "$repo#5 1 stall-window" "$(stalled "$(R --stall-window 60)")"
fixture
R >/dev/null
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "ship 0.54.2: preflight refused, the issue is not triaged."
check "ship's first reply or an early stop carries the version but is no gate summary" "$repo#5 1 run-completed" "$(stalled "$(R)")"
fixture
R >/dev/null
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "Unmet criteria: none, but I stopped before the gate."
check "the Unmet criteria item without ship's version is no gate summary" "$repo#5 1 run-completed" "$(stalled "$(R)")"
fixture
R >/dev/null
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "A relationship 1.2.3 of tickets, and I stopped."
check "a message that only contains 'ship 1.2.3' inside another word is no gate summary" "$repo#5 1 run-completed" "$(stalled "$(R)")"
sa_thread t-6 idle 0 0 /wt/6 feat/x-6
R >/dev/null
L set "$repo#6" rest_since "\"$old\"" >/dev/null
check "a thread that never started stalls once the window passes" "$repo#6 1 stall-window" "$(stalled "$(R --stall-window 60)")"
check "--stall-window takes a positive integer" 2 "$(bash "$s/reconcile.sh" --ledger "$led" --stall-window 0 >/dev/null 2>&1; echo $?)"

# --- never by process name, and an empty ledger is fine -------------------------
check "no process was asked about" "" "$(cat "$SA_FAKE/proc-calls" 2>/dev/null)"
rm -f "$led"
out=$(R); rc=$?
check_rc "an empty ledger exits 0" 0 "$rc"
check "and checks nothing" 0 "$(jq .checked <<<"$out")"


# --- a merged PR settles only once its thread is at rest -----------------------
fixture
sa_pr $repo feat/x-5 merged
out=$(R)
check "a merged PR with its thread still running is merged, not settled" merged "$(stage 5)"
check "so nothing is settled" "[]" "$(jq -c .settled <<<"$out")"
check "and the entry stays open for the watcher" 1 "$(L list --open | jq '[.entries[] | select(.key == "'$repo'#5")] | length')"
sa_thread t-5 idle 2 0 /wt/5 feat/x-5
out=$(R)
check "the thread at rest settles it" settled "$(stage 5)"
check "naming it once" "$repo#5" "$(jq -r '.settled[].key' <<<"$out")"

# --- a triage entry has no PR: it ends when the label is gone ------------------
rm -f "$led"
L add --repo $repo --number 9 --thread t-9 --worktree /wt/9 --branch triage/x-9 --kind triage >/dev/null
check "the entry records its kind" triage "$(L get $repo#9 | jq -r .kind)"
check "an entry added without one is ship" ship "$(L add --repo $repo --number 10 --thread t-10 --worktree /wt/10 --branch b-10 | jq -r .entry.kind)"
sa_pr $repo triage/x-9 none
sa_thread t-9 idle 0 0 /wt/9 triage/x-9
sa_issue $repo 9 open ready-for-agent
R >/dev/null
check "a triage thread that has not run yet is not settled by an absent label" at-rest "$(stage 9)"
sa_thread t-9 running 1 0 /wt/9 triage/x-9
sa_issue $repo 9 open needs-triage
R >/dev/null
sa_thread t-9 idle 1 0 /wt/9 triage/x-9
out=$(R)
check "a run done with the issue still needs-triage is no end" at-rest "$(stage 9)"
sa_issue $repo 9 open ready-for-agent
out=$(R)
check "a run done and the label gone settles it, with no PR" settled "$(stage 9)"
check "the summary says it was a triage entry" "$repo#9 triage" "$(jq -r '.settled[] | "\(.key) \(.kind)"' <<<"$out")"
rm -f "$led"
L add --repo $repo --number 9 --thread t-9 --worktree /wt/9 --branch triage/x-9 --kind triage >/dev/null
sa_thread t-9 running 1 0 /wt/9 triage/x-9
sa_issue $repo 9 open ready-for-agent
R >/dev/null
check "a triage run still running is not settled by the label alone" running "$(stage 9)"
# a grill waits on the owner: at rest, no needs-triage, needs-info set
rm -f "$led"
L add --repo $repo --number 9 --thread t-9 --worktree /wt/9 --branch triage/x-9 --kind triage >/dev/null
sa_thread t-9 idle 1 0 /wt/9 triage/x-9
sa_issue $repo 9 open needs-info
R >/dev/null
check "a triage run at rest on needs-info is no end" at-rest "$(stage 9)"
sa_issue $repo 9 open ready-for-agent
out=$(R)
check "the same run once needs-info is gone settles" settled "$(stage 9)"

# a settled triage entry whose thread runs again is reopened and reported
rm -f "$SA_FAKE/calls"
out=$(R)
check "a settled triage entry with the same run count is not reported" "[]" "$(jq -c .woke <<<"$out")"
check "and stays settled" settled "$(stage 9)"
check "and costs no PR or issue call" "" "$(calls | grep '^gh ' || true)"
sa_thread t-9 running 2 0 /wt/9 triage/x-9
out=$(R)
check "a settled triage thread that runs again is reported in woke" "$repo#9 t-9 triage" "$(jq -r '.woke[] | "\(.key) \(.thread) \(.kind)"' <<<"$out")"
check "and its stage is running" running "$(stage 9)"
check "and it counts as checked on the next reconcile" 1 "$(R | jq .checked)"
sa_thread t-9 idle 3 0 /wt/9 triage/x-9
out=$(R)
check "the resumed run ending with the issue clear settles it again" settled "$(stage 9)"

out=$(L add --repo $repo --number 11 --thread t-11 --worktree /wt/11 --branch b-11 --kind other 2>/dev/null); rc=$?
check_rc "a kind outside ship and triage is a usage error" 2 "$rc"

# --- one failed PR read is retried ---------------------------------------------
fixture
sa_gh_fail "/pulls" 1
out=$(R)
check "one failed PR read then success reads the PR" "[]" "$(jq -c .errors <<<"$out")"
check "and the entry is observed" running "$(stage 5)"
fixture
sa_gh_fail "/pulls" 2
out=$(R)
check "two failed reads report the PR unreadable" "$repo#5 pr-unreadable" "$(jq -r '.errors[0] | "\(.key) \(.kind)"' <<<"$out")"
rm -f "$SA_FAKE/gh-fail"

finish
