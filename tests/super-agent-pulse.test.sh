#!/usr/bin/env bash
# super-agent's `pulse`, driven through its command line over fake `t3` and `gh`
# on PATH (tests/super-agent-fake.sh): one call answers whether the watcher is
# alive and whether the backstop turn has anything to act on. Stamps are fixed:
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
P() { bash "$s/pulse.sh" --ledger "$led" "$@"; }
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
R() { bash "$s/reconcile.sh" --ledger "$led" "$@"; }

# fixture: ticket 5, launched, a running thread, no PR, an open issue
fixture() {
  rm -f "$led" "$led.watch" "$SA_FAKE/calls"
  L add --repo $repo --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null
  sa_thread t-5 running 1 0 /wt/5 feat/x-5
  sa_pr $repo feat/x-5 none
  sa_issue $repo 5 open
}
# a live process whose command line is a watch.sh, as the lock's pid
watcher() {
  mkdir -p "$tmp/w"; printf '#!/usr/bin/env bash\n/usr/bin/sleep 30\n' > "$tmp/w/watch.sh"
  bash "$tmp/w/watch.sh" & wpid=$!
  printf '%s\n' "$wpid" > "$led.watch"
}
stop() { pkill -P "$wpid" 2>/dev/null; kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null; }

# --- the contract every script keeps -------------------------------------------
out=$(bash "$s/pulse.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: pulse" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/pulse.sh" --nope 2>/dev/null); rc=$?
check "a malformed call answers its usage line" "$(sed -n 1p <<<"$(bash "$s/pulse.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a malformed call exits 2" 2 "$rc"
check_rc "no ledger exits 2" 2 "$(bash "$s/pulse.sh" >/dev/null 2>&1; echo $?)"
check_rc "a --stall-window of 0 exits 2" 2 "$(P --stall-window 0 >/dev/null 2>&1; echo $?)"

# --- a quiet wake with a live watcher ends the turn ----------------------------
fixture
R >/dev/null
watcher
out=$(P); rc=$?
check_rc "a pulse exits 0" 0 "$rc"
check "one JSON object is the whole answer" 1 "$(jq -s length <<<"$out")"
check "a live watcher with nothing changed is alive and quiet" "true false null" "$(jq -r '[.alive, .changed, (.summary | tostring)] | join(" ")' <<<"$out")"
stop
out=$(P)
check "a lock holding a dead pid is a dead watcher" false "$(jq .alive <<<"$out")"
rm -f "$led.watch"
check "no lock is a dead watcher" false "$(P | jq .alive)"
/usr/bin/sleep 30 & other=$!
printf '%s\n' "$other" > "$led.watch"
check "a live process that is no watch.sh is a dead watcher" false "$(P | jq .alive)"
kill "$other" 2>/dev/null; wait "$other" 2>/dev/null

# --- a change carries reconcile's answer ---------------------------------------
fixture
R >/dev/null
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "Stopped after the tests."
sa_pr $repo feat/x-5 open
watcher
out=$(P)
check "a stage that moved is a change" true "$(jq .changed <<<"$out")"
check "and the summary is the reconcile answer" "$repo#5 running at-rest" \
  "$(jq -r '.summary.entries[] | "\(.key) \(.from) \(.stage)"' <<<"$out")"
check "and a stall counted by it is named" "$repo#5 run-completed" "$(jq -r '.summary.stalled[] | "\(.key) \(.reason)"' <<<"$out")"
out=$(P)
check "the same rest seen again is quiet: an entry at rest is no change" "true false null" \
  "$(jq -r '[.alive, .changed, (.summary | tostring)] | join(" ")' <<<"$out")"
stop

fixture
R >/dev/null
sa_pr $repo feat/x-5 merged
sa_thread t-5 idle 2 0 /wt/5 feat/x-5
watcher
out=$(P)
check "a merged entry is a change carrying its cleanup and verify rows" "$repo#5 $repo#5" \
  "$(jq -r '[.summary.cleanup[0].key, .summary.verify[0].key] | join(" ")' <<<"$out")"
L set "$repo#5" cleanup_owed false >/dev/null
L set "$repo#5" verify_owed false >/dev/null
check "once cleared it is quiet again" "false" "$(P | jq .changed)"
stop

fixture
R >/dev/null
sa_thread t-5 idle 4 1 /wt/5 feat/x-5 "Stopped."
R >/dev/null
watcher
out=$(P)
check "an escalate row is a change on its own" "true $repo#5" "$(jq -r '[.changed, .summary.escalate[0].key] | join(" ")' <<<"$out")"
stop

fixture
R >/dev/null
rm "$SA_FAKE/threads/t-5.json"
check "an error row is a change" true "$(P | jq .changed)"
L need "$repo#5" --action "refresh the thread read" >/dev/null
check "an entry's error with its need recorded is not" false "$(P | jq .changed)"
sa_issue $repo 30 open
L wait "$repo#31" --reason r >/dev/null
check "an error of a waiting row, which no entry carries, is" true "$(P | jq .changed)"
rm -f "$led"
check "a ledger that does not exist yet is quiet" false "$(P | jq .changed)"

# --- a failing reconcile is relayed --------------------------------------------
rm -f "$led"
printf 'not json\n' > "$led"
out=$(P 2>/dev/null); rc=$?
check_rc "an unreadable ledger exits 2" 2 "$rc"
check "with reconcile's own error" true "$(jq -e 'has("error")' <<<"$out" >/dev/null 2>&1 && echo true || echo false)"

# --- the flags reach reconcile -------------------------------------------------
fixture
R >/dev/null
sa_thread t-5 idle 1 0 /wt/5 feat/x-5 "Stopped after the tests."
R --stall-window 60 >/dev/null
L set "$repo#5" rest_since '"2020-01-01T00:00:00Z"' >/dev/null
out=$(P --stall-window 60)
check "--stall-window is passed on" "$repo#5 stall-window" "$(jq -r '.summary.stalled[] | "\(.key) \(.reason)"' <<<"$out")"
printf '{"active_repos":["%s"]}\n' "$repo" > "$tmp/fleet.json"
check "--fleet is passed on" 0 "$(P --fleet "$tmp/fleet.json" >/dev/null 2>&1; echo $?)"
check "a fleet file reconcile refuses is relayed as exit 2" 2 "$(printf 'x' > "$tmp/bad.json"; P --fleet "$tmp/bad.json" >/dev/null 2>&1; echo $?)"

finish
