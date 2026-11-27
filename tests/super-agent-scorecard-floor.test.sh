#!/usr/bin/env bash
# super-agent's `scorecard` and the context floor cut (#1385): a day's row counts
# the context floor after a fresh start and after a compaction (each the median
# of the first call's context), and the calls or ToolSearch queries that name a
# tool, server or skill the super agent folder's settings cut; the weekly review
# sums that count.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-launch-lib.sh

export HOME=$tmp/home CLAUDE_CONFIG_DIR='' T3CODE_THREAD_ID='' XDG_STATE_HOME=$tmp/state
day=2026-11-19
R() { bash "$s/scorecard.sh" row --ledger "$led" --version 9.9.9 "$@"; }
u() { jq -cn --arg ts "$1" --arg t "$2" --argjson c "${3:-false}" '{type: "user", timestamp: $ts, isCompactSummary: $c, message: {role: "user", content: $t}}'; }
# a <ts> <message id> <context tokens> [<tool use JSON>...]
a() { local ts=$1 id=$2 n=$3; shift 3
  jq -cn --arg ts "$ts" --arg id "$id" --argjson n "$n" --argjson t "$(printf '%s\n' "$@" | jq -sc .)" \
    '{type: "assistant", timestamp: $ts, message: {id: $id, model: "claude-x",
      usage: {input_tokens: 10, cache_creation_input_tokens: ($n - 10), cache_read_input_tokens: 0, output_tokens: 5},
      content: ([{type: "text", text: "ok"}] + $t)}}'; }
tool() { jq -cn --arg n "$1" --argjson i "${2:-{\}}" '{type: "tool_use", id: "t", name: $n, input: $i}'; }

{ u "${day}T10:00:00Z" "start"; a "${day}T10:00:05Z" m1 60000 "$(tool Artifact)"
  a "${day}T10:00:09Z" m2 61000 "$(tool ToolSearch '{"query":"select:mcp__claude_ai_Exa__web_search_exa,mcp__t3-code__t3_thread_read"}')"
  u "${day}T12:00:00Z" "summary" true; a "${day}T12:00:05Z" m3 70000 "$(tool Skill '{"skill":"tdd"}')"
  a "${day}T12:00:09Z" m4 71000 "$(tool mcp__claude_ai_Exa__web_fetch_exa)" "$(tool ToolSearch '{"query":"+slack tdd-helper"}')"
  u "${day}T14:00:00Z" "summary" true; a "${day}T14:00:05Z" m5 80000 "$(tool Bash '{"command":"ls"}')" "$(tool ToolSearch '{"query":"\"Agent\""}')"
} > "$tmp/a.jsonl"
{ u "${day}T16:00:00Z" "start"; a "${day}T16:00:05Z" m6 30000; } > "$tmp/b.jsonl"

out=$(R --day "$day" --transcript "$tmp/a.jsonl" --transcript "$tmp/b.jsonl")
check "the fresh floor is the median first call of the day's sessions, the compacted one of the calls after each summary" \
  '{"fresh":45000,"compacted":75000}' "$(jq -c .row.floor <<<"$out")"
check "with no folder settings to read, the cut's count is null" null "$(jq -c .row.denied <<<"$out")"

mkdir -p "$XDG_STATE_HOME/super-agent/home/.claude"
jq -n '{permissions: {deny: ["Artifact", "Agent", "mcp__claude_ai_Exa"]}, skillOverrides: {tdd: "off"}}' \
  > "$XDG_STATE_HOME/super-agent/home/.claude/settings.json"
out=$(R --day "$day" --transcript "$tmp/a.jsonl" --transcript "$tmp/b.jsonl")
check "a denied tool, a denied server's tool, a switched-off skill and a ToolSearch naming one, quoted or not, each count, a near name does not" \
  '{"calls":5}' "$(jq -c .row.denied <<<"$out")"
for d in 17 18 20 21 22 23; do R --day "2026-11-$d" --transcript "$tmp/a.jsonl" >/dev/null; done
check "the review sums the week's count" 5 \
  "$(bash "$s/scorecard.sh" review --ledger "$led" --week 2026-11-17 | jq .denied.calls)"

finish
