#!/usr/bin/env bash
# Replay: the super agent's own turn died (a limit stop, an auth error) or a host
# restart cancelled its watcher, with the ledger holding open work, and nothing
# woke it for up to 46 minutes (8 of the 14 no-watcher cases, 6 to 23 Nov; issue
# #1380, decision #1329). The incident version is the scripts at f33fce3e, which
# have no wake timer: only a watcher's exit or the hourly backstop woke the
# super agent, and a dead turn had neither. The fixture is hand-built through
# tests/super-agent-fake.sh: one open entry observed, the lock absent, the super
# agent's own thread idle. Fixed: the timer's ticks send one wake line, run the
# notify command once when no reconcile follows, and do nothing more while the
# outage lasts.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake/threads"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json fleet=$tmp/fleet.json hits=$tmp/hits
bash "$s/ledger.sh" --ledger "$led" add --repo Gharib89/skills --number 5 --thread t-5 \
  --worktree /wt/5 --branch feat/x-5 >/dev/null
bash "$s/ledger.sh" --ledger "$led" set Gharib89/skills#5 observed \
  '{"status":"running","run_count":1,"pending":0,"pr":{"number":null,"state":"none"}}' >/dev/null
bash "$s/ledger.sh" --ledger "$led" self sa-1 >/dev/null
sa_thread sa-1 idle 4 0 '' '' 'Prompt is too long' 2026-11-25T10:00:00Z
jq -n --arg c "printf '%s\\n' \"\$SA_NOTIFY_MESSAGE\" >> $hits" '{machines: {}, notify: {command: $c}}' > "$fleet"
T=1795000000
tick() { SA_NOW=$((T + $1)) bash "$s/wake-timer.sh" --ledger "$led" --fleet "$fleet" >/dev/null; }
sends() { grep -c '^t3 thread send' "$SA_FAKE/calls"; }

tick 0; tick 300
check "an owed watcher and an idle thread: one wake line" \
  "t3 thread send sa-1 Wake timer: no watcher is running. Run pulse and restart the watcher." \
  "$(grep '^t3 thread send' "$SA_FAKE/calls")"
check "no notify before the delay" 0 "$([ -f "$hits" ] && wc -l < "$hits" || echo 0)"
tick 600; tick 900; tick 1500
check "no reconcile followed: one notify, and no second wake" "1 1" "$(wc -l < "$hits") $(sends)"

finish
