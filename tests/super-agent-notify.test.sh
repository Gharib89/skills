#!/usr/bin/env bash
# super-agent's notify command, driven through the command lines of `notify`,
# `watch` and `reconcile` over fake `t3` and `gh` (tests/super-agent-fake.sh): a
# watcher that exits on an event leaves a detached `notify` behind, which runs the
# fleet file's command once when no reconcile followed within the delay and
# nothing when one did; a timeout exit leaves none, and a fleet file without a
# notify command behaves as before.
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
led=$tmp/ledger.json fleet=$tmp/fleet.json hits=$tmp/hits
repo=Gharib89/skills
N() { bash "$s/notify.sh" --ledger "$led" --fleet "$fleet" "$@"; }
count() { [ -f "$hits" ] && wc -l < "$hits" | tr -d ' ' || echo 0; }
fleet_with() { jq -n --arg c "$1" --argjson d "$2" '{machines: {}, notify: {command: $c, delay: $d}}' > "$fleet"; }
fire_cmd="printf '%s\\n' \"\$SA_NOTIFY_MESSAGE\" >> $hits"

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/notify.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: notify" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/notify.sh" --bogus 2>/dev/null); rc=$?
check "a bad flag answers the usage line" "$(sed -n 1p <<<"$(bash "$s/notify.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad flag exits 2" 2 "$rc"
check_rc "a missing --since exits 2" 2 "$(N >/dev/null 2>&1; echo $?)"

# --- notify itself: no stamp fires, a stamp at or after --since does not ---------
rm -f "$hits" "$led.reconciled"
fleet_with "$fire_cmd" 1
out=$(N --since 100); rc=$?
check_rc "with no reconcile it exits 0" 0 "$rc"
check "it ran the command once, with the message in SA_NOTIFY_MESSAGE" '{"notified":true,"exit":0} 1' "$(jq -c '{notified, exit}' <<<"$out") $(count)"
check "the message says how long nobody reconciled" 1 "$(grep -c 'super agent' "$hits")"

rm -f "$hits"; printf '100\n' > "$led.reconciled"
out=$(N --since 100)
check "a reconcile at --since runs nothing" '{"notified":false,"reason":"reconciled"} 0' "$(jq -c '{notified, reason}' <<<"$out") $(count)"
printf '99\n' > "$led.reconciled"
out=$(N --since 100)
check "a reconcile before --since does not count" 'true 1' "$(jq -r .notified <<<"$out") $(count)"

jq 'del(.notify)' "$fleet" > "$tmp/none.json"; rm -f "$hits" "$led.reconciled"
out=$(bash "$s/notify.sh" --ledger "$led" --fleet "$tmp/none.json" --since 100); rc=$?
check "a fleet file with no notify command runs nothing and exits 0" '0 false 0' "$rc $(jq -r .notified <<<"$out") $(count)"

for bad in '{"command":""}' '{"delay":5}' '{"command":"x","delay":0}' '{"command":"x","delay":1.5}' '{"command":"x","delay":"5"}' '"x"'; do
  jq -n --argjson n "$bad" '{machines: {}, notify: $n}' > "$tmp/bad.json"
  out=$(bash "$s/notify.sh" --ledger "$led" --fleet "$tmp/bad.json" --since 100 2>/dev/null); rc=$?
  check "notify $bad exits 2 naming the field" "2 1" "$rc $(jq -r .error <<<"$out" | grep -c notify)"
done

# --- reconcile stamps the ledger's sidecar --------------------------------------
fixture() {
  rm -f "$led" "$led.reconciled" "$SA_FAKE/calls" "$hits"
  for n in 5 6; do
    bash "$s/ledger.sh" --ledger "$led" add --repo $repo --number $n --thread "t-$n" \
      --worktree "/wt/$n" --branch "feat/x-$n" >/dev/null
    bash "$s/ledger.sh" --ledger "$led" set "$repo#$n" observed '{"status":"running","run_count":1,"pending":0,"pr":{"number":null,"state":"none"}}' >/dev/null
    sa_thread "t-$n" running 1 0 "/wt/$n" "feat/x-$n"
    sa_pr $repo "feat/x-$n" none
    sa_issue $repo "$n" open 2>/dev/null
  done
}
fixture
SA_NOW=1700000000 bash "$s/reconcile.sh" --ledger "$led" >/dev/null
check "a reconcile writes the epoch second it ran at" 1700000000 "$(cat "$led.reconciled" 2>/dev/null)"

# --- watch leaves a detached notify behind on an event ---------------------------
W() { bash "$s/watch.sh" --ledger "$led" --interval 1 --recheck 0 "$@"; }
finish_t5() { sa_thread t-5 idle 1 0 /wt/5 feat/x-5; }
await() { for _ in 1 2 3 4 5 6 7 8; do [ "$(count)" -ge "$1" ] && return 0; sleep 1; done; return 0; }

fixture; finish_t5; fleet_with "$fire_cmd" 1
out=$(W --timeout 5 --fleet "$fleet")
check "the watcher still reports its event" "run-finished" "$(jq -r .event <<<"$out")"
await 1
check "no reconcile within the delay: the command ran" 1 "$(count)"
sleep 2
check "and only once" 1 "$(count)"

fixture; finish_t5; fleet_with "$fire_cmd" 2
W --timeout 5 --fleet "$fleet" >/dev/null
bash "$s/reconcile.sh" --ledger "$led" >/dev/null
sleep 4
check "a reconcile within the delay: nothing ran" 0 "$(count)"

fixture; finish_t5; fleet_with "$fire_cmd" 1
W --timeout 5 >/dev/null
sleep 3
check "a watcher started without --fleet runs nothing" 0 "$(count)"

fixture; fleet_with "$fire_cmd" 1
out=$(W --timeout 2 --fleet "$fleet")
sleep 3
check "a timeout is no event: nothing ran" "timeout 0" "$(jq -r .event <<<"$out") $(count)"

fixture; jq -n '{machines: {}, notify: {command: "x", delay: 0}}' > "$tmp/bad.json"
out=$(W --timeout 2 --fleet "$tmp/bad.json" 2>/dev/null); rc=$?
check "a watcher with a bad notify exits 2 before it polls" "2" "$rc"

finish
