#!/usr/bin/env bash
# Replay case: on 2026-11-25 the ship run for the wake timer (#1380, PR #1417)
# found that the scorecard sorted the wake timer's own line ("Wake timer: no
# watcher is running...") into cause `owner`, so every timer wake would count as
# the owner's (#1416). A wake the wake timer sent now counts under its own cause,
# `wake timer`, and an owner's wake stays the owner's. Red on v0.47.0's
# scorecard.sh, which reads {"owner":2}.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-launch-lib.sh

export HOME=$tmp/home CLAUDE_CONFIG_DIR='' T3CODE_THREAD_ID=''
day=2026-11-19
u() { jq -cn --arg ts "$1" --arg t "$2" '{type: "user", timestamp: $ts, message: {role: "user", content: $t}}'; }
a() { jq -cn --arg ts "$1" --arg id "$2" '{type: "assistant", timestamp: $ts,
  message: {id: $id, model: "claude-x", usage: {input_tokens: 1, output_tokens: 1}, content: [{type: "text", text: "ok"}]}}'; }

bash "$s/ledger.sh" --ledger "$led" add --repo "$repo" --number 7 --thread th-7 --worktree /wt/7 --branch b-7 >/dev/null
{ u "${day}T10:00:00Z" "why is #7 still open?"; a "${day}T10:00:05Z" m1
  u "${day}T11:00:00Z" "Wake timer: no watcher is running. Run pulse and restart the watcher."; a "${day}T11:00:05Z" m2
} > "$tmp/t.jsonl"
check "a wake timer wake counts as cause wake timer, and the owner's wake stays the owner's" \
  '{"owner":1,"wake timer":1}' \
  "$(bash "$s/scorecard.sh" row --ledger "$led" --day "$day" --transcript "$tmp/t.jsonl" --version 9.9.9 | jq -c .row.wakes.by_cause)"

finish
