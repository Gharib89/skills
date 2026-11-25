#!/usr/bin/env bash
# Replay: the super agent's turn ended with the ledger holding an open, observed
# entry and no watcher on the lock (issue #1379, filed 2026-11-24; decision
# #1317). The rule "No turn ends without a watcher running while the ledger
# holds an open entry" was one SKILL.md sentence, so nothing stopped the turn
# and nothing woke the super agent again. The incident version is the scripts at
# 9aba9663, which have no `watch.sh --owed` and no watch guard. The fixture is
# hand-built through tests/super-agent-fake.sh: one open entry, observed
# running, the lock absent. Fixed: the first stop is blocked, the second (the
# hook input says a stop hook is already active) passes, and both are logged.
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
led=$tmp/ledger.json fleet=$tmp/fleet.json log=$tmp/watch-guard.jsonl
bash "$s/ledger.sh" --ledger "$led" add --repo Gharib89/skills --number 5 --thread t-5 \
  --worktree /wt/5 --branch feat/x-5 >/dev/null
bash "$s/ledger.sh" --ledger "$led" set Gharib89/skills#5 observed \
  '{"status":"running","run_count":1,"pending":0,"pr":{"number":null,"state":"none"}}' >/dev/null
H() { bash "$s/watch-guard.sh" --ledger "$led" --fleet "$fleet" <<<"$1"; }

first=$(H '{"hook_event_name":"Stop","stop_hook_active":false}')
check "the first stop with a watcher owed is blocked" block "$(jq -r .decision <<<"$first")"
second=$(H '{"hook_event_name":"Stop","stop_hook_active":true}'); rc=$?
check "the second stop passes with no output" "0 " "$rc $second"
check "and the log holds the block, then the pass" "block pass" \
  "$(jq -r .event "$log" | tr '\n' ' ' | sed 's/ $//')"

finish
