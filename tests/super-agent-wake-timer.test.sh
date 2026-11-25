#!/usr/bin/env bash
# super-agent's wake timer, driven through its command line over fake `t3`,
# `notify-send` and `systemctl` (tests/super-agent-fake.sh), one tick per call
# with the clock set by SA_NOW: a running thread is left alone, a limit stop is
# held until its reset plus 10 minutes, a permission request pending over 10
# minutes is notified, a T3 that does not answer falls back to the desktop
# notifier, and each outage is logged as JSON lines.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
T=1795000000
# fresh: a new state dir holding one open, observed entry, the super agent's own
# thread `sa-1` and a fleet file whose notify command appends to `hits`.
fresh() {
  d=$tmp/$1; mkdir -p "$d/fake/threads"; : > "$d/fake/calls"
  export SA_FAKE=$d/fake
  led=$d/ledger.json fleet=$d/fleet.json hits=$d/hits log=$d/wake-timer.jsonl
  bash "$s/ledger.sh" --ledger "$led" add --repo Gharib89/skills --number 5 --thread t-5 \
    --worktree /wt/5 --branch feat/x-5 >/dev/null
  bash "$s/ledger.sh" --ledger "$led" set Gharib89/skills#5 observed \
    '{"status":"running","run_count":1,"pending":0,"pr":{"number":null,"state":"none"}}' >/dev/null
  bash "$s/ledger.sh" --ledger "$led" self sa-1 >/dev/null
  jq -n --arg c "printf '%s\\n' \"\$SA_NOTIFY_MESSAGE\" >> $hits" '{machines: {}, notify: {command: $c}}' > "$fleet"
}
tick() { SA_NOW=$((T + $1)) bash "$s/wake-timer.sh" --ledger "$led" --fleet "$fleet"; }
sends() { grep -c '^t3 thread send' "$SA_FAKE/calls" || :; }
notified() { [ -f "$hits" ] && wc -l < "$hits" | tr -d ' ' || echo 0; }
events() { [ -f "$log" ] && jq -r .event "$log" | tr '\n' ' ' | sed 's/ $//'; }

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/wake-timer.sh" --help); rc=$?
check "--help opens with its usage line" "usage: wake-timer" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
bash "$s/wake-timer.sh" --bogus >/dev/null 2>&1; check_rc "an unknown flag is a usage error" 2 $?

# --- a running thread is the watch guard's --------------------------------------
fresh running
sa_thread sa-1 running 4 0 '' ''
out=$(tick 0; tick 900)
check "a running thread: no wake, no notify; the outage opens when owed is first seen" "0 0 opened" "$(sends) $(notified) $(events)"
check "and the answer says why" running "$(tail -1 <<<"$out" | jq -r .action)"

# --- nothing owed ---------------------------------------------------------------
fresh none
sa_thread sa-1 idle 4 0 '' ''
: > "$led.watch"  # an empty lock reads as a live watcher
out=$(tick 0)
check "a live watcher's lock: nothing owed, nothing sent" "none 0" "$(jq -r .owed <<<"$out") $(sends)"
rm -f "$led.watch"

# --- a limit stop is held until its reset plus 10 minutes ------------------------
fresh limit
# rested 10:00 UTC; the line names 18:10 UTC, so the reset is 18:10 that day
sa_thread sa-1 idle 4 0 '' '' "You've hit your limit · resets 6:10pm (UTC)" 2026-11-25T10:00:00Z
R=$(date -u -d '2026-11-25 18:10' +%s)
out=$(SA_NOW=$((R + 599)) bash "$s/wake-timer.sh" --ledger "$led" --fleet "$fleet")
check "before the reset plus 10 minutes: held, no wake, no outage" "held 0 " "$(jq -r .action <<<"$out") $(sends) $(events)"
SA_NOW=$((R + 600)) bash "$s/wake-timer.sh" --ledger "$led" --fleet "$fleet" >/dev/null
check "at the reset plus 10 minutes: one wake" 1 "$(sends)"
fresh limit-open
sa_thread sa-1 running 4 0 '' ''
SA_NOW=$((R - 3600)) bash "$s/wake-timer.sh" --ledger "$led" --fleet "$fleet" >/dev/null
sa_thread sa-1 idle 4 0 '' '' "You've hit your limit · resets 6:10pm (UTC)" 2026-11-25T10:00:00Z
SA_NOW=$R bash "$s/wake-timer.sh" --ledger "$led" --fleet "$fleet" >/dev/null
SA_NOW=$((R + 600)) bash "$s/wake-timer.sh" --ledger "$led" --fleet "$fleet" >/dev/null
check "an outage open when the hold starts closes there, so the hold is not counted" \
  "opened closed opened wake 60" "$(events) $(jq -r 'select(.event == "closed") | .minutes' "$log")"
fresh limit-unread
sa_thread sa-1 idle 4 0 '' '' "You've hit your limit · resets 6:10pm (Nowhere/Zone)" 2026-11-25T10:00:00Z
tick 0 >/dev/null
check "an unreadable reset falls through to a wake" 1 "$(sends)"

# --- a pending permission request over 10 minutes is notified -------------------
fresh pending
sa_thread sa-1 running 4 1 '' ''
tick 0 >/dev/null; tick 599 >/dev/null
check "pending under 10 minutes: nothing" "0 0" "$(sends) $(notified)"
tick 600 >/dev/null; tick 1200 >/dev/null
check "pending at 10 minutes: one notify, no wake" "1 0" "$(notified) $(sends)"
check "the notify names the pending request" 1 "$(grep -c 'permission request' "$hits")"

# --- T3 not answering -----------------------------------------------------------
fresh t3-down
SA_T3_RC=1 tick 0 >/dev/null
SA_T3_RC=1 tick 300 >/dev/null
check "a failing t3: the desktop notifier, once" 1 "$(grep -c '^notify-send' "$SA_FAKE/calls")"
check "and its log" desktop "$(jq -r 'select(.event == "notify") | .via' "$log")"
check "the notify command is not run while T3 is down" 0 "$(notified)"

# --- a failed send runs the notify command --------------------------------------
fresh send-fails
sa_thread sa-1 idle 4 0 '' ''
SA_T3_SEND_RC=1 tick 0 >/dev/null
check "a failed send: the notify command runs once" 1 "$(notified)"

# --- a malformed notify does not silence the tick ------------------------------
fresh bad-notify
sa_thread sa-1 idle 4 0 '' ''
SA_T3_SEND_RC=1 bash -c 'echo "{\"notify\": 5}" > "$1"' _ "$fleet"
out=$(SA_T3_SEND_RC=1 tick 0); rc=$?
check "a malformed notify: exit 0, the desktop notifier names the fault" "0 notify 1" \
  "$rc $(jq -r .action <<<"$out") $(grep -c '^notify-send.*malformed notify' "$SA_FAKE/calls")"
out=$(SA_T3_SEND_RC=1 tick 300)
check "a later tick, already notified, only waits" "waiting 1" "$(jq -r .action <<<"$out") $(grep -c '^notify-send' "$SA_FAKE/calls")"

# --- a broken state file is refused, never reset into a second wake ------------------
fresh broken
sa_thread sa-1 idle 4 0 '' ''
tick 0 >/dev/null
printf 'partial' > "$d/wake-timer.state.json"
out=$(tick 60)
check "a state file that is no JSON object: no second wake, the desktop notifier names it" \
  "unjudged 1 1 partial" \
  "$(jq -r .action <<<"$out") $(sends) $(grep -c '^notify-send.*wake-timer.state.json' "$SA_FAKE/calls") $(cat "$d/wake-timer.state.json")"

# --- the outage log --------------------------------------------------------------
fresh log
sa_thread sa-1 idle 4 0 '' ''
tick 0 >/dev/null; tick 599 >/dev/null
check "no notify a second before the delay" 0 "$(notified)"
tick 600 >/dev/null
# A real reconcile writes the stamp the tick closes the outage on.
mkdir -p "$SA_FAKE/gh"; sa_thread t-5 running 1 0 /wt/5 feat/x-5; sa_pr Gharib89/skills feat/x-5 none; sa_issue Gharib89/skills 5 open 2>/dev/null
SA_NOW=$((T + 700)) bash "$s/reconcile.sh" --ledger "$led" >/dev/null
check "a reconcile writes the epoch second it ran at" $((T + 700)) "$(cat "$led.reconciled" 2>/dev/null)"
tick 900 >/dev/null
check "one outage: opened, wake sent, notify run, closed; still owed, the next opens" "opened wake notify closed opened wake" "$(events)"
check "closed carries the outage minutes, open to reconcile" 12 "$(jq -r 'select(.event == "closed") | .minutes' "$log")"
: > "$led.watch"  # an empty lock reads as a live watcher
tick 1200 >/dev/null
check "a watcher no longer owed closes the outage" "closed closed" "$(jq -r 'select(.event == "closed") | .event' "$log" | tr '\n' ' ' | sed 's/ $//')"

finish
