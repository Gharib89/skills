#!/usr/bin/env bash
# super-agent's `launch` refusals that need a launchable ticket: a --note holding
# a newline, a fleet whose merge_gate_ruler is neither owner nor super-agent, and a
# route that prints nothing. Each exits 2 with no argument object.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-launch-lib.sh

reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
out=$(L 7 --note "$(printf 'Check A.\nThen B.')" 2>/dev/null); rc=$?
check "a --note holding a newline exits 2 naming the newline, never launching, so the message keeps one Note: line" "2 false 1" \
  "$rc $(jq -r 'has("args")' <<<"$out") $(jq -r .error <<<"$out" | grep -c "note holds a newline")"

# --- who rules on a merge-gate hold: a fleet value other than owner or super-agent is no launch ---
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
for v in owner super-agent; do
  jq --arg v "$v" '.merge_gate_ruler = $v' "$fleet" > "$tmp/ruler.json"
  check "a merge_gate_ruler of $v launches" true \
    "$(bash "$s/launch.sh" "$repo#7" --fleet "$tmp/ruler.json" --ledger "$led" --quota "$quota" --machine home --thread th-super --area x | jq .launch)"
done
for v in '"anyone"' 3; do
  jq --argjson v "$v" '.merge_gate_ruler = $v' "$fleet" > "$tmp/ruler.json"
  out=$(bash "$s/launch.sh" "$repo#7" --fleet "$tmp/ruler.json" --ledger "$led" --quota "$quota" --machine home --thread th-super --area x 2>/dev/null); rc=$?
  check "a merge_gate_ruler of $v exits 2 naming the field, never launching" "2 false 1" \
    "$rc $(jq -r 'has("args")' <<<"$out") $(jq -r .error <<<"$out" | grep -c merge_gate_ruler)"
done
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
rm -rf "$tmp/stub"; cp -r "$s" "$tmp/stub"; printf 'exit 0\n' > "$tmp/stub/route.sh"
out=$(bash "$tmp/stub/launch.sh" "$repo#7" --fleet "$fleet" --ledger "$led" --quota "$quota" --machine home --thread th-super --area x 2>&1); rc=$?
check "a route that prints nothing exits 2 with a named error, never launching" "2 false route gave no answer" "$rc $(jq -r 'has("args")' <<<"$out") $(jq -r .error <<<"$out")"
reset

finish
