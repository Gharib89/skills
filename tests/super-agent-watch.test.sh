#!/usr/bin/env bash
# super-agent's `watch`, driven through its command line over fake `t3` and `gh`
# on PATH (tests/super-agent-fake.sh): it exits printing the first change in a
# supervised thread or its PR, keeps polling while nothing changes, and finds a
# thread by its id and worktree path, never by a process name.
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
W() { bash "$s/watch.sh" --ledger "$led" --interval 1 --recheck 0 "$@"; }
calls() { cat "$SA_FAKE/calls" 2>/dev/null; }
base='{"status":"running","run_count":1,"pending":0,"pr":{"number":null,"state":"none"}}'

# fixture <stage-of-6>: two tickets, 5 and 6, each observed running its first run
fixture() {
  rm -f "$led" "$SA_FAKE/calls" "$SA_FAKE/proc-calls"
  for n in 5 6; do
    bash "$s/ledger.sh" --ledger "$led" add --repo $repo --number $n --thread "t-$n" \
      --worktree "/wt/$n" --branch "feat/x-$n" >/dev/null
    bash "$s/ledger.sh" --ledger "$led" set "$repo#$n" observed "$base" >/dev/null
    sa_thread "t-$n" running 1 0 "/wt/$n" "feat/x-$n"
    sa_pr $repo "feat/x-$n" none
  done
  [ "${1:-}" = settled ] && bash "$s/ledger.sh" --ledger "$led" set "$repo#6" stage '"settled"' >/dev/null
  return 0
}
event() { jq -r '[(.key // "null"), .event] | join(" ")' <<<"$1"; }

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/watch.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: watch" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/watch.sh" --interval 0 2>/dev/null); rc=$?
check "a malformed call answers its usage line" "$(sed -n 1p <<<"$(bash "$s/watch.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a malformed call exits 2" 2 "$rc"

# --- nothing changes: it keeps polling until its timeout ----------------------
fixture
out=$(W --timeout 2); rc=$?
check_rc "with no change it runs to its timeout and exits 0" 0 "$rc"
check "and says it saw nothing" "null timeout" "$(event "$out")"
check "naming what it watched" "$repo#5 $repo#6" "$(jq -r '.watching | join(" ")' <<<"$out")"
check "it polled every thread more than once" 1 "$(( $(calls | grep -c '^t3 thread show t-5 ') > 1 ))"

# --- each change is an event ---------------------------------------------------
fixture
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
out=$(W --timeout 5); rc=$?
check_rc "a finished run exits 0" 0 "$rc"
check "a run that went from running to rest is run-finished" "$repo#5 run-finished" "$(event "$out")"
check "the event names the thread and what it saw" '{"thread":"t-5","status":"idle","run_count":1}' \
  "$(jq -c '{thread, status: .observed.status, run_count: .observed.run_count}' <<<"$out")"
check "watch writes nothing: the finished run is reported again" "$repo#5 run-finished" "$(event "$(W --timeout 5)")"

fixture
sa_thread t-5 running 2 0 /wt/5 feat/x-5
check "a new run is no event: a run starting is not worth a wake" "null timeout" "$(event "$(W --timeout 2)")"
sa_thread t-5 idle 2 0 /wt/5 feat/x-5
check "a new run that already ended is run-finished" "$repo#5 run-finished" "$(event "$(W --timeout 5)")"

fixture
sa_thread t-6 running 1 1 /wt/6 feat/x-6
check "a permission hold is a change: pending-approval" "$repo#6 pending-approval" "$(event "$(W --timeout 5)")"

fixture
sa_pr $repo feat/x-5 merged
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
out=$(W --timeout 5)
check "a merged PR is pr-merged, ahead of the run that finished with it" "$repo#5 pr-merged" "$(event "$out")"
check "and the event carries the PR" '{"number":7,"state":"merged"}' "$(jq -c .observed.pr <<<"$out")"

fixture
sa_pr $repo feat/x-5 closed
check "a PR closed unmerged is pr-closed" "$repo#5 pr-closed" "$(event "$(W --timeout 5)")"

fixture
sa_pr $repo feat/x-5 open
check "a PR opened is no event" "null timeout" "$(event "$(W --timeout 2)")"

fixture
sa_thread t-6 idle 1 0 /wt/6 feat/x-6
check "a change in the second ticket reports that ticket" "$repo#6 run-finished" "$(event "$(W --timeout 5)")"
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
check "with two changes, the ledger's order decides" "$repo#5 run-finished" "$(event "$(W --timeout 5)")"

# --- a thread is found by id and worktree path, never by process name ----------
fixture
W --timeout 2 >/dev/null
check "watch asked t3 for each thread by the id the ledger holds" \
  "t3 thread show t-5 --json --messages 1" "$(calls | grep -m1 '^t3 thread show t-5 ')"
check "and asked nothing about processes" "" "$(cat "$SA_FAKE/proc-calls" 2>/dev/null)"

fixture
sa_thread t-5 running 1 0 /elsewhere/5 feat/x-5
out=$(W --timeout 5)
check "a thread of that id in another worktree is thread-mismatch" "$repo#5 thread-mismatch" "$(event "$out")"
check "and says which path it found" "/elsewhere/5" "$(jq -r .detail.worktree <<<"$out")"

fixture
sa_thread t-5 running 1 0 /wt/5 feat/x-5
jq -c '.thread.threadId = "t-other"' "$SA_FAKE/threads/t-5.json" > "$tmp/x" && mv "$tmp/x" "$SA_FAKE/threads/t-5.json"
check "an answer for another thread id is thread-mismatch" "$repo#5 thread-mismatch" "$(event "$(W --timeout 5)")"

# --- a run that finished is rechecked before it is reported --------------------
fixture
sa_thread t-5 running 2 0 /wt/5 feat/x-5
cp "$SA_FAKE/threads/t-5.json" "$tmp/running.json"
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
printf 'cp "%s" "$SA_FAKE/threads/t-5.json"\n' "$tmp/running.json" > "$SA_FAKE/on-sleep"
out=$(bash "$s/watch.sh" --ledger "$led" --interval 1 --recheck 1 --timeout 3)
check "a run that restarts within the recheck is no event" "null timeout" "$(event "$out")"
fixture
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
check "one still at rest after the recheck is run-finished" "$repo#5 run-finished" \
  "$(event "$(bash "$s/watch.sh" --ledger "$led" --interval 1 --recheck 1 --timeout 5)")"

fixture
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
printf 'rm -f "%s/threads/t-5.json"\n' "$SA_FAKE" > "$SA_FAKE/on-sleep"
check "a fault in the recheck look is reported, not the stale run-finished" "$repo#5 thread-unreadable" \
  "$(event "$(bash "$s/watch.sh" --ledger "$led" --interval 1 --recheck 1 --timeout 5)")"

# --- the stall window: at rest, with no new run, for too long ------------------
old=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)
fixture
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
bash "$s/ledger.sh" --ledger "$led" set "$repo#5" observed '{"status":"idle","run_count":1,"pending":0,"pr":{"number":null,"state":"none"},"gate":false}' >/dev/null
bash "$s/ledger.sh" --ledger "$led" set "$repo#5" rest_since "\"$old\"" >/dev/null
check "a thread at rest past the window is stall-window" "$repo#5 stall-window" "$(event "$(W --timeout 5 --stall-window 60)")"
check "not before it" "null timeout" "$(event "$(W --timeout 2 --stall-window 86400)")"
bash "$s/ledger.sh" --ledger "$led" set "$repo#5" stalls 3 >/dev/null
check "an entry already at 3 stalls is escalated, so its window is quiet" "null timeout" "$(event "$(W --timeout 2 --stall-window 60)")"
bash "$s/ledger.sh" --ledger "$led" set "$repo#5" stalls 1 >/dev/null
sa_thread t-5 running 2 0 /wt/5 feat/x-5
check "a thread that started again is no stall" "null timeout" "$(event "$(W --timeout 2 --stall-window 60)")"
sa_thread t-5 idle 1 1 /wt/5 feat/x-5
check "a thread holding a permission request is pending-approval, not a stall" "$repo#5 pending-approval" "$(event "$(W --timeout 5 --stall-window 60)")"
check "--stall-window takes a positive integer" 2 "$(bash "$s/watch.sh" --ledger "$led" --stall-window 0 >/dev/null 2>&1; echo $?)"

# --- what it cannot read is an event, not a silent stall -----------------------
fixture
rm "$SA_FAKE/threads/t-5.json"
check "a thread the server does not know is thread-unreadable" "$repo#5 thread-unreadable" "$(event "$(W --timeout 5)")"
fixture
check "a thread whose read exits nonzero is thread-unreadable, whatever it printed" "$repo#5 thread-unreadable" \
  "$(event "$(SA_T3_RC=1 W --timeout 5)")"
fixture
jq -c 'del(.thread.runCount)' "$SA_FAKE/threads/t-5.json" > "$tmp/x" && mv "$tmp/x" "$SA_FAKE/threads/t-5.json"
check "a thread answer without its run count is thread-unreadable, not a quiet null" "$repo#5 thread-unreadable" \
  "$(event "$(W --timeout 5)")"
fixture
rm "$SA_FAKE/gh/"*x-5*
check "a PR list GitHub will not answer is pr-unreadable" "$repo#5 pr-unreadable" "$(event "$(W --timeout 5)")"

# --- which entries it watches --------------------------------------------------
fixture settled
rm "$SA_FAKE/threads/t-6.json"
out=$(W --timeout 2)
check "a settled entry is not watched, so its missing thread is no event" "null timeout" "$(event "$out")"
check "and is not in what it names" "$repo#5" "$(jq -r '.watching | join(" ")' <<<"$out")"
check "t3 was never asked about it" "" "$(calls | grep '^t3 thread show t-6 ')"

fixture
bash "$s/ledger.sh" --ledger "$led" add --repo $repo --number 9 --thread t-9 --worktree /wt/9 --branch feat/x-9 >/dev/null
out=$(W --timeout 2 2>/dev/null); rc=$?
check_rc "one entry nothing has observed yet does not stop the others" 0 "$rc"
check "the others are still watched" "$repo#5 $repo#6" "$(jq -r '.watching | join(" ")' <<<"$out")"
check "and it is named, not dropped silently" "$repo#9" "$(jq -r '.unobserved | join(" ")' <<<"$out")"
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
check "a change in an observed entry still wakes it" "$repo#5 run-finished" "$(event "$(W --timeout 5)")"

fixture
rm "$led"
bash "$s/ledger.sh" --ledger "$led" add --repo $repo --number 9 --thread t-9 --worktree /wt/9 --branch feat/x-9 >/dev/null
out=$(W --timeout 2 2>/dev/null); rc=$?
check_rc "a ledger where nothing is observed yet exits 1" 1 "$rc"
check "and asks for a reconcile first" "$repo#9 has no observed state: run reconcile first" "$(jq -r .error <<<"$out")"

# a fault reconcile already recorded does not wake a restarted watcher again
fixture
rm "$SA_FAKE/threads/t-5.json"
check "a thread fault is reported once by the watcher" "$repo#5 thread-unreadable" "$(event "$(W --timeout 5)")"
bash "$s/ledger.sh" --ledger "$led" set "$repo#5" error '"thread-unreadable"' >/dev/null
out=$(W --timeout 3)
check "and not again once reconcile recorded it" "null timeout" "$(event "$out")"
sa_thread t-6 idle 1 0 /wt/6 feat/x-6
check "while the entry after it is still polled" "$repo#6 run-finished" "$(event "$(W --timeout 5)")"
bash "$s/ledger.sh" --ledger "$led" set "$repo#5" error '"pr-unreadable"' >/dev/null
sa_thread t-6 running 1 0 /wt/6 feat/x-6
check "a different fault than the recorded one is reported" "$repo#5 thread-unreadable" "$(event "$(W --timeout 5)")"

fixture
for n in 5 6; do bash "$s/ledger.sh" --ledger "$led" set "$repo#$n" stage '"closed"' >/dev/null; done
out=$(W --timeout 2 2>/dev/null); rc=$?
check_rc "a ledger with nothing open exits 1" 1 "$rc"
check "and says so" "no open entry in the ledger $led" "$(jq -r .error <<<"$out")"

fixture
before=$(cat "$led")
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
W --timeout 5 >/dev/null
check "watch leaves the ledger as it found it" "$before" "$(cat "$led")"


# --- a merged entry is watched until its thread rests --------------------------
fixture
bash "$s/ledger.sh" --ledger "$led" set "$repo#5" stage '"merged"' >/dev/null
bash "$s/ledger.sh" --ledger "$led" set "$repo#5" observed '{"status":"running","run_count":1,"pending":0,"pr":{"number":7,"state":"merged"}}' >/dev/null
sa_pr $repo feat/x-5 merged
out=$(W --timeout 2)
check "a merged entry whose thread still runs wakes nothing" "null timeout" "$(event "$out")"
check "and is still watched" "$repo#5 $repo#6" "$(jq -r '.watching | join(" ")' <<<"$out")"
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
check "its thread coming to rest is run-finished" "$repo#5 run-finished" "$(event "$(W --timeout 5)")"

# --- an entry added while a watcher runs is watched ----------------------------
fixture
bash "$s/ledger.sh" --ledger "$led" set "$repo#6" stage '"settled"' >/dev/null
cat > "$SA_FAKE/on-sleep" <<EOS
bash "$s/ledger.sh" --ledger "$led" add --repo $repo --number 7 --thread t-7 --worktree /wt/7 --branch feat/x-7 >/dev/null
bash "$s/ledger.sh" --ledger "$led" set "$repo#7" observed '$base' >/dev/null
EOS
sa_thread t-7 idle 1 0 /wt/7 feat/x-7
sa_pr $repo feat/x-7 none
check "an entry added and observed mid-watch is reported when its run finished" "$repo#7 run-finished" "$(event "$(W --timeout 6)")"

# --- one watcher per ledger ----------------------------------------------------
fixture
W --timeout 6 >"$tmp/first.out" 2>&1 &
first=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$led.watch" ] && break; /usr/bin/sleep 0.2; done  # the real sleep, past the fake on PATH
out=$(W --timeout 1 2>/dev/null); rc=$?
check_rc "a second start while one runs exits 1" 1 "$rc"
check "and reports the one running, the pid the lock holds" "$(cat "$led.watch")" "$(jq -r .running <<<"$out")"
kill "$first" 2>/dev/null; wait "$first" 2>/dev/null
rm -f "$led.watch"
: > "$led.watch"
fixture
out=$(W --timeout 1 2>/dev/null); rc=$?
check_rc "a lock that reads empty is kept, not taken over" 1 "$rc"
rm -f "$led.watch"
fixture
echo 999999 > "$led.watch"
out=$(W --timeout 1); rc=$?
check_rc "a pid file of a dead watcher is taken over" 0 "$rc"
check "and the lock is released at exit" "no" "$([ -f "$led.watch" ] && echo yes || echo no)"

finish
