#!/usr/bin/env bash
# Replay: the owner asked "why is this issue still open" and the super agent answered
# by trying to close it (12 Nov, issue #1387; decision #1316). 3 of 11 "why" asks were
# answered by an action, and the rule that an owner question changes nothing was no
# script's: nothing marked the turn and nothing recorded the call. The incident version
# is the scripts at fc40660c, which have no question flag and no observe hook. The
# fixture is the incident's two hook inputs, built by hand: the owner's prompt, typed
# with no T3 sender prefix, and the `gh issue close` call the turn then made, both
# carrying the one prompt id Claude Code gives a turn's hooks. Fixed: the prompt is
# flagged, the close is logged against its id and still passes, and the next turn's
# calls are not logged.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
led=$tmp/ledger.json log=$tmp/question-flag.jsonl
prompt=$(jq -cn '{hook_event_name: "UserPromptSubmit", prompt: "why is this issue still open", prompt_id: "9f1c"}')
asked=$(jq -cn '{hook_event_name: "UserPromptSubmit", prompt: "why is this issue still open?", prompt_id: "9f1d"}')
close() { jq -cn --arg id "$1" '{hook_event_name: "PreToolUse", prompt_id: $id, tool_name: "Bash", tool_input: {command: "gh issue close 1234 -R acme/widgets"}}'; }

out=$(bash "$s/question-flag.sh" --ledger "$led" <<<"$prompt")
check "a prompt with no ? is not flagged" "" "$out"
out=$(bash "$s/question-flag.sh" --ledger "$led" <<<"$asked")
check "the owner's question is flagged" 1 "$(grep -c '^Question flag:' <<<"$out")"
out=$(bash "$s/observe.sh" --ledger "$led" <<<"$(close 9f1d)"); rc=$?
check "the close the turn then made passes, with no output" "0 " "$rc $out"
check "and is logged against the prompt's id" "9f1d Bash gh issue close 1234 -R acme/widgets" \
  "$(jq -r 'select(.event == "changing") | "\(.prompt_id) \(.tool) \(.call)"' "$log")"
bash "$s/observe.sh" --ledger "$led" <<<"$(close 9f1e)" >/dev/null
check "the next turn's close is not logged" 1 "$(jq -s '[.[] | select(.event == "changing")] | length' "$log")"

finish
