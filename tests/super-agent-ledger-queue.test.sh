#!/usr/bin/env bash
# super-agent's `ledger wait` as the owner's queue, driven through its command
# line over a fixture ledger: a row's order and `--after` blocker, the list
# printing in order, and a repeat keeping what it is not given.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
led=$tmp/ledger.json
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }

# --- the owner's queue: a waiting row takes an order and a blocker -----------------------
L wait Gharib89/skills#41 --reason queued --order 2 >/dev/null
L wait Gharib89/skills#42 --reason queued --order 1 >/dev/null
L wait Gharib89/skills#43 --reason queued >/dev/null
out=$(L wait Gharib89/skills#44 --reason "after 42" --after Gharib89/skills#42)
check "a row holds its order and its blocker" '{"key":"Gharib89/skills#44","order":null,"after":"Gharib89/skills#42"}' \
  "$(jq -c '.waiting | {key, order, after}' <<<"$out")"
check "the waiting list prints ordered rows first, then the rest as they were added" \
  '["Gharib89/skills#42","Gharib89/skills#41","Gharib89/skills#43","Gharib89/skills#44"]' "$(L list | jq -c '[.waiting[].key]')"
L wait Gharib89/skills#43 --reason "still queued" >/dev/null
check "a repeat without --order or --after keeps them" '{"order":null,"after":null,"reason":"still queued"}' \
  "$(L list | jq -c '.waiting[] | select(.key == "Gharib89/skills#43") | {order, after, reason}')"
L wait Gharib89/skills#44 --reason "after 42" >/dev/null
check "and keeps a blocker too" Gharib89/skills#42 "$(L list | jq -r '.waiting[] | select(.key == "Gharib89/skills#44") | .after')"
L wait Gharib89/skills#43 --reason "first now" --order 0 >/dev/null
check "a repeat with --order replaces it, and 0 is first" Gharib89/skills#43 "$(L list | jq -r '.waiting[0].key')"
check_rc "an order that is no whole number exits 2" 2 "$(L wait Gharib89/skills#45 --reason r --order x >/dev/null 2>&1; echo $?)"
check_rc "a blocker that is no repo and number exits 2" 2 "$(L wait Gharib89/skills#45 --reason r --after nope >/dev/null 2>&1; echo $?)"
check "the largest order, 9 digits, is taken and sorts before an unordered row" true "$(L wait Gharib89/skills#45 --reason r >/dev/null; L wait Gharib89/skills#46 --reason r --order 999999999 >/dev/null; L list | jq '[.waiting[].key] | index("Gharib89/skills#46") < index("Gharib89/skills#45")')"
check_rc "an order of 10 digits exits 2" 2 "$(L wait Gharib89/skills#47 --reason r --order 1000000000 >/dev/null 2>&1; echo $?)"
for n in 41 42 43 44 45 46; do L unwait Gharib89/skills#$n >/dev/null; done

finish
