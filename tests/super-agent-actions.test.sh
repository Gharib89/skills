#!/usr/bin/env bash
# super-agent's `reconcile` actions, driven through its command line over fake
# `t3` and `gh` on PATH (tests/super-agent-fake.sh): a rest on the waiting line is
# running, and the `cleanup`, `verify` and `escalate` lists name what the super
# agent owes after a wake. Stamps are fixed (2099 inside any window, 2020 past it):
# no test reads the clock.
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
# shellcheck disable=SC2120 # this file passes no flags
R() { bash "$s/reconcile.sh" --ledger "$led" "$@"; }
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
stage() { jq -r --arg k "$repo#$1" '.entries[$k].stage' "$led"; }
stalls() { jq -r --arg k "$repo#$1" '.entries[$k].stalls' "$led"; }
stalled() { jq -r '[.stalled[] | "\(.key) \(.stalls) \(.reason)"] | join(",")' <<<"$1"; }

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

# --- the waiting line: a thread at rest on it is still working ------------------
wl='Waiting on my own background work.'
inside=2099-01-01T00:00:00Z past=2020-01-01T00:00:00Z # fixed stamps: no clock read
fixture
R >/dev/null
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "Checks are running.
$wl" $inside
out=$(R)
check "a rest on the waiting line inside the window is running" running "$(stage 5)"
check "and no stall" "" "$(stalled "$out")"
check "its count stays 0" 0 "$(stalls 5)"
check "and it is not listed at rest" "[]" "$(jq -c .at_rest <<<"$out")"
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "Checks are running.
$wl" $past
out=$(R)
check "the same rest past the window is at-rest" at-rest "$(stage 5)"
check "and the run that completed is a stall at once" "$repo#5 1 run-completed" "$(stalled "$out")"
# the window's edge, with the clock taken from the test
edge=$(date -u -d "$inside" +%s) # a fixed stamp converted, no clock read
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "$wl" $inside
check "one second inside the window it is still running" running "$(SA_NOW=$((edge + 59)) R --stall-window 60 >/dev/null; stage 5)"
SA_NOW=$((edge + 60)) R --stall-window 60 >/dev/null
check "at the window it is at-rest" at-rest "$(stage 5)"
sa_thread t-5 idle 2 0 /wt/5 feat/x-5 "$wl is not my last line.
Stopped." $inside
check "a message that does not end on the waiting line is a rest" at-rest "$(R >/dev/null; stage 5)"
fixture
sa_pr $repo feat/x-5 merged
sa_thread t-5 idle 2 0 /wt/5 feat/x-5 "$wl" $inside
R >/dev/null
check "a merged PR whose thread waits inside the window stays merged" merged "$(stage 5)"
sa_thread t-5 idle 2 0 /wt/5 feat/x-5 "$wl" $past
R >/dev/null
check "and settles once the window has passed" settled "$(stage 5)"

# --- cleanup: what the super agent owes after an entry ends --------------------
cleanup() { jq -r '[.cleanup[] | "\(.key) \(.thread) \(.worktree) \(.kind) \(.stage)"] | join(",")' <<<"$1"; }
fixture
sa_pr $repo feat/x-5 merged
sa_thread t-5 idle 2 0 /wt/5 feat/x-5
out=$(R)
check "a merged ship entry has a cleanup row naming its thread and worktree" "$repo#5 t-5 /wt/5 ship settled" "$(cleanup "$out")"
check "the row carries the environment (null for a local thread)" null "$(jq -c '.cleanup[0].environment_id' <<<"$out")"
check "the ledger marks the cleanup owed" true "$(jq -r --arg k "$repo#5" '.entries[$k].cleanup_owed' "$led")"
check "only the ended entry has a row" "$repo#5" "$(jq -r '[.cleanup[].key] | join(",")' <<<"$out")"
check "the row stays until the super agent clears it" "$repo#5 t-5 /wt/5 ship settled" "$(cleanup "$(R)")"
L set "$repo#5" cleanup_owed false >/dev/null
check "clearing it ends the row" "" "$(cleanup "$(R)")"
fixture
sa_pr $repo feat/x-5 closed
out=$(R)
check "a closed entry has a cleanup row too" "$repo#5 t-5 /wt/5 ship closed" "$(cleanup "$out")"
fixture
sa_pr $repo feat/x-5 merged
sa_thread t-5 idle 2 0 /wt/5 feat/x-5
R >/dev/null
L rethread "$repo#5" --thread t-9 --worktree /wt/9 --branch feat/x-9 >/dev/null
check "a rethread clears the owed cleanup and verification" "null null" \
  "$(jq -r --arg k "$repo#5" '.entries[$k] | "\(.cleanup_owed) \(.verify_owed)"' "$led")"
rm -f "$led"
L add --repo $repo --number 7 --thread t-7 --worktree /wt/7 --branch triage/x-7 --kind triage >/dev/null
sa_thread t-7 idle 1 0 /wt/7 triage/x-7; sa_pr $repo triage/x-7 none; sa_issue $repo 7 open ready-for-agent
check "a settled triage entry has a cleanup row of its kind" "$repo#7 t-7 /wt/7 triage settled" "$(cleanup "$(R)")"
rm -f "$led"
L add --repo $repo --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null
sa_stage "$led" "$repo#5" settled
check "a settled entry from before this field has no row" "" "$(cleanup "$(R)")"

# --- verify: a merged ship PR whose criteria check is not recorded -------------
verify() { jq -r '[.verify[] | "\(.key) \(.repo) \(.number) \(.pr) \(.stage)"] | join(",")' <<<"$1"; }
fixture
sa_pr $repo feat/x-5 merged
out=$(R)
check "a merged PR whose thread still runs is owed a verify" "$repo#5 $repo 5 7 merged" "$(verify "$out")"
sa_thread t-5 idle 2 0 /wt/5 feat/x-5
out=$(R)
check "and the row follows it to settled" "$repo#5 $repo 5 7 settled" "$(verify "$out")"
L set "$repo#5" verify_owed false >/dev/null
check "recording the check ends the row" "" "$(verify "$(R)")"
fixture
sa_pr $repo feat/x-5 open
check "a PR not yet merged has none" "" "$(verify "$(R)")"
fixture
sa_pr $repo feat/x-5 closed
check "nor a PR closed unmerged" "" "$(verify "$(R)")"
rm -f "$led"
L add --task t1 --thread t-8 --worktree /wt/8 --branch b-8 >/dev/null
sa_thread t-8 idle 1 0 /wt/8 b-8
check "nor a task entry" "" "$(verify "$(R)")"

# --- escalate: what only the owner can unblock ---------------------------------
esc() { jq -r '[.escalate[] | "\(.key) \(.reason)"] | join(",")' <<<"$1"; }
fixture
sa_thread t-5 idle 4 1 /wt/5 feat/x-5 "Stopped after the tests."
out=$(R)
check "a thread holding a permission request is escalated" "$repo#5 permission-hold" "$(esc "$out")"
check "and the other ticket is not" "$repo#5" "$(jq -r '[.escalate[].key] | join(",")' <<<"$out")"
check "the row names the thread" t-5 "$(jq -r '.escalate[0].thread' <<<"$out")"
check "it repeats until the owner's need is recorded" "$repo#5 permission-hold" "$(esc "$(R)")"
L need "$repo#5" --action "answer the permission dialog" >/dev/null
check "an open need silences it" "" "$(esc "$(R)")"
fixture
rm "$SA_FAKE/threads/t-5.json"
out=$(R)
check "a recorded fault is escalated, naming its kind" "$repo#5 fault thread-unreadable" "$(jq -r '.escalate[] | "\(.key) \(.reason) \(.detail)"' <<<"$out")"
fixture
R >/dev/null
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "Stopped."
L set "$repo#5" stalls 3 >/dev/null
check "a stall at the cap is escalated" "$repo#5 stall-cap" "$(esc "$(R)")"
sa_thread t-5 running 2 0 /wt/5 feat/x-5
check "but not while its thread runs" "" "$(esc "$(R)")"
fixture
R >/dev/null
sa_thread t-5 idle 4 1 /wt/5 feat/x-5 "Stopped."
L set "$repo#5" stalls 3 >/dev/null
check "an entry with two causes gets one row, the permission hold first" "$repo#5 permission-hold" "$(esc "$(R)")"
fixture
sa_pr $repo feat/x-5 closed
out=$(R)
check "a PR closed unmerged is escalated until its cleanup is done" "$repo#5 pr-closed" "$(esc "$out")"
L set "$repo#5" cleanup_owed false >/dev/null
check "and not after" "" "$(esc "$(R)")"
fixture
sa_issue $repo 6 closed
check "a closed issue is escalated as issue-closed" "$repo#6 issue-closed" "$(esc "$(R)")"
fixture
sa_pr $repo feat/x-5 merged
sa_thread t-5 idle 2 0 /wt/5 feat/x-5
check "a merged entry needs no owner" "" "$(esc "$(R)")"
check "no list is empty by absence: each action list is an array" "array array array" \
  "$(jq -r '[(.cleanup | type), (.verify | type), (.escalate | type)] | join(" ")' <<<"$(R)")"
check "--help lists the new fields" "cleanup escalate verify" \
  "$(bash "$s/reconcile.sh" --help | grep -o 'cleanup\|verify\|escalate' | sort -u | tr '\n' ' ' | sed 's/ $//')"

finish
