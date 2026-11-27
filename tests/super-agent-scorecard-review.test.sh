#!/usr/bin/env bash
# super-agent's `scorecard review`, driven through its command line: a week of
# hand-built rows read against the targets (the day's row: super-agent-scorecard.test.sh).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-launch-lib.sh

export HOME=$tmp/home CLAUDE_CONFIG_DIR='' T3CODE_THREAD_ID=''
sc=$s/scorecard.sh
card=$(dirname "$led")/scorecard.jsonl
bash "$s/ledger.sh" --ledger "$led" self th-own >/dev/null

# --- the weekly review over a full week ----------------------------------------
cat > "$tmp/targets.json" <<'JSON'
{"needs.alerted_twice": {"max": 0}, "timer.worst_minutes": {"max": 15}}
JSON
rowfor() { # <day> <alerted twice> <worst minutes> <watch blocks or "">
  jq -cn --arg d "$1" --argjson n "$2" --argjson m "$3" --arg b "${4:-}" \
    '{day: $d, messages: {count: 500}, needs: {alerted_twice: $n}, timer: {worst_minutes: $m},
      guards: (if $b == "" then null else {watch: {blocks: ($b | tonumber), passes: 0}} end)}'
}
week() { # the week of 9 to 15 Nov, with the given alerted-twice count on its Wednesday
  for d in 09 10 11 12 13 14 15; do rowfor "2026-11-$d" "$([ "$d" = 11 ] && echo "$1" || echo 0)" 10 "${2:-}"; done
}
V() { SA_NOW=$(jq -n '"2026-11-18T08:00:00Z" | fromdateiso8601') bash "$sc" review --ledger "$led" --targets "$tmp/targets.json" "$@"; }
week 0 > "$card"
out=$(V); rc=$?
check "a week where every target holds prints nothing, and the default week is the last full one" \
  '0 {"from":"2026-11-09","to":"2026-11-15"} 7 []' "$rc $(jq -c .week <<<"$out") $(jq .days <<<"$out") $(jq -c .needs <<<"$out")"
week 2 > "$card"
check "a number that missed its target is one row naming it (a number with no target raises none)" \
  '["Scorecard: needs.alerted_twice missed its target of 0 on 1 of 7 days (worst 2)."]' "$(V | jq -c .needs)"
jq -n '{"needs.alerted_twice": {max: 0, slice: 12}}' > "$tmp/pending.json"
week 0 | jq -c 'if .day == "2026-11-12" then .questions = {asked: 1, with_write: 1, turns: [{prompt_id: "p9", at: "2026-11-12T10:00:00Z", calls: [{tool: "Edit", call: "/a"}, {tool: "Edit", call: "/b"}]}]} else . end' > "$card"
check "the review lists each owner question turn that held a changing call" \
  '["Scorecard: the owner question at 2026-11-12T10:00:00Z (prompt p9) held a changing call: Edit; read the turn and take its sender from t3_thread_read."]' "$(V | jq -c .needs)"
week 2 > "$card"
check "a target still tagged with its slice raises no row" '[]' \
  "$(SA_NOW=$(jq -n '"2026-11-18T08:00:00Z" | fromdateiso8601') bash "$sc" review --ledger "$led" --targets "$tmp/pending.json" | jq -c .needs)"
{ for d in 19 20 21 22 23 24 25 26 27 28 29 30; do rowfor "2026-10-$d" 0 10 0; done
  for d in 01 02 03 04 05 06 07 08; do rowfor "2026-11-$d" 0 10 0; done; week 0 0; } > "$card"
check "a guard with zero blocks for four weeks is one row" \
  '["Scorecard: the watch guard blocked nothing for four weeks; delete it?"]' "$(V | jq -c .needs)"
{ for d in 20 21 22 23 24 25 26 27 28 29 30; do rowfor "2026-10-$d" 0 10 0; done
  for d in 01 02 03 04 05 06 07 08; do rowfor "2026-11-$d" 0 10 0; done; week 0 0; } > "$card"
check "a guard logged for less than four weeks raises none" '[]' "$(V | jq -c .needs)"
{ for d in 19 20 21 22 23 24 25 26 27 28 29 30; do rowfor "2026-10-$d" 0 10 0; done
  rowfor 2026-11-01 0 10 1; for d in 02 03 04 05 06 07 08; do rowfor "2026-11-$d" 0 10 0; done; week 0 0; } > "$card"
check "a guard that blocked once in the four weeks raises none" '[]' "$(V | jq -c .needs)"
{ rowfor 2026-09-01 0 10 0; week 0; } > "$card"
check "a guard logged before the four weeks but not in each of them raises none" '[]' "$(V | jq -c .needs)"
week 0 | grep -v 2026-11-15 > "$card"
check "a week missing a day's row is refused by name, exit 2" \
  '2 review failed: week 2026-11-09: no row for 2026-11-15; count it with row --day' \
  "$(out=$(V 2>/dev/null); echo "$? $(jq -r .error <<<"$out")")"
: > "$card"
check "a week with no row at all raises nothing" '0 []' "$(out=$(V); echo "$? $(jq -c .needs <<<"$out")")"
week 0 > "$card"; jq -n '{"needs.alerted_twice": 0}' > "$tmp/bad.json"
check "a target that is no {max} is refused, exit 2" 2 \
  "$(SA_NOW=$(jq -n '"2026-11-18T08:00:00Z" | fromdateiso8601') bash "$sc" review --ledger "$led" --targets "$tmp/bad.json" >/dev/null 2>&1; echo $?)"
for d in 02 03 04 05 06 07 08; do rowfor "2026-11-$d" 0 10; done > "$card"
check "--week reviews the week given" '{"from":"2026-11-02","to":"2026-11-08"} 7' \
  "$(V --week 2026-11-02 | jq -r '"\(.week | tojson) \(.days)"')"

# the review sums a week's refusals and raises no row for them
week 0 | jq -c 'if .day == "2026-11-10" then .call_guard = {refused: 2, told: 0} elif .day == "2026-11-13" then .call_guard = {refused: 3, told: 1} else .call_guard = {refused: 0, told: 0} end' > "$card"
check "the review counts the week's call guard refusals" '{"refused":5}' "$(V | jq -c .call_guard)"
check "and raises no row for them" '[]' "$(V | jq -c .needs)"
week 0 | jq -c 'del(.call_guard)' > "$card"
check "a week of rows with no call_guard counts 0" '{"refused":0}' "$(V | jq -c .call_guard)"

finish
