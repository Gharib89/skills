#!/usr/bin/env bash
# super-agent's `status`, driven through its command line over fixture ledgers:
# each row of the block, an empty ledger, the no-change answer, the new-need
# answer and the digest form.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
led=$tmp/ledger.json
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
S() { bash "$s/status.sh" --ledger "$led" "$@"; }
add() { L add --repo Gharib89/skills --number "$1" --thread "t-$1" --worktree "/wt/$1" --branch "b-$1" >/dev/null; }
stage() { L set "Gharib89/skills#$1" stage "\"$2\"" >/dev/null; }
obs() { L set "Gharib89/skills#$1" observed "$2" >/dev/null; }

# --- the contract every script keeps -------------------------------------------
out=$(bash "$s/status.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: status" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/status.sh" 2>/dev/null); rc=$?
check "a bare call answers its usage line" "$(sed -n 1p <<<"$(bash "$s/status.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bare call exits 2" 2 "$rc"

# --- an empty ledger: nothing to post ------------------------------------------
out=$(S); rc=$?
check_rc "no ledger file exits 0" 0 "$rc"
check "an empty ledger prints no block and no change" '{"block":"","changed":false,"unpushed":[]}' "$(jq -c '{block, changed, unpushed}' <<<"$out")"
check "a digest of an empty ledger prints no block either" '' "$(S --digest | jq -r .block)"

# --- each row, in order, an empty row left out ---------------------------------
for n in 650 655 674 689 658 660; do add "$n"; done
stage 650 merged; obs 650 '{"gate":false,"pr":{"number":679,"state":"merged"}}'
stage 655 settled; obs 655 '{"gate":false,"pr":{"number":685,"state":"merged"}}'
stage 674 running; obs 674 '{"gate":true,"pr":{"number":690,"state":"open"}}'
stage 689 at-rest; obs 689 '{"gate":false,"pr":{"number":691,"state":"open"}}'
jq 'del(.entries["Gharib89/skills#658"], .entries["Gharib89/skills#660"])' "$led" > "$tmp/l" && mv "$tmp/l" "$led"
L wait Gharib89/skills#658 --reason r >/dev/null
L wait Gharib89/skills#660 --reason r >/dev/null
L wait Gharib89/skills#686 --reason r >/dev/null
u=https://github.com/Gharib89/skills
want="Merged (2): [skills#650]($u/issues/650) PR [679]($u/pull/679), [skills#655]($u/issues/655) PR [685]($u/pull/685)
Running (2): [skills#674]($u/issues/674) at its merge gate, [skills#689]($u/issues/689) in review
Waiting (3): [skills#658]($u/issues/658), [skills#660]($u/issues/660), [skills#686]($u/issues/686)"
out=$(S)
check "the block holds Merged, Running and Waiting in order, as links, with no Needs row" "$want" "$(jq -r .block <<<"$out")"
check "the first block reports a change" true "$(jq .changed <<<"$out")"
out=$(S)
check "run twice with no ledger change, the second reports no change" false "$(jq .changed <<<"$out")"
check "and prints no block" '' "$(jq -r .block <<<"$out")"
check "a digest prints the whole block whatever changed" "$want" "$(S --digest | jq -r .block)"
check "and a run after the digest still reports no change" false "$(S | jq .changed)"
check "the digest cleared Merged: a later digest leaves it out" "$(sed 1d <<<"$want")" "$(S --digest | jq -r .block)"

# --- Running reads the stage when no PR or gate says more ----------------------
add 700; add 701
stage 701 running
check "a launched ticket reads launched, a running one running" \
  "Running (4): [skills#674]($u/issues/674) at its merge gate, [skills#689]($u/issues/689) in review, [skills#700]($u/issues/700) launched, [skills#701]($u/issues/701) running" \
  "$(S | jq -r .block | grep '^Running')"
check "an entry's change moves the row" false "$(obs 701 '{"gate":false,"pr":{"number":9,"state":"open"}}'; S | jq '.changed | not')"

# --- a new need: first row, unpushed once --------------------------------------
L need Gharib89/skills#681 --action "pick backfill or forward-only" >/dev/null
out=$(S)
check "a need makes Needs you the first row" "Needs you (1): [skills#681]($u/issues/681) pick backfill or forward-only" "$(jq -r '.block | split("\n")[0]' <<<"$out")"
check "and the run reports a change" true "$(jq .changed <<<"$out")"
check "listing the need not yet pushed" '[{"key":"Gharib89/skills#681","action":"pick backfill or forward-only"}]' "$(jq -c '[.unpushed[] | {key, action}]' <<<"$out")"
L pushed Gharib89/skills#681 >/dev/null
out=$(S)
check "marking it pushed lists none and changes no row" 'false []' "$(jq -r '"\(.changed) \(.unpushed)"' <<<"$out")"
check "a digest keeps the need row first" "Needs you (1): [skills#681]($u/issues/681) pick backfill or forward-only" "$(S --digest | jq -r '.block | split("\n")[0]')"
L need Gharib89/skills#682 --action "approve the held merge" >/dev/null
out=$(S)
check "a second need is one more row item and only it is unpushed" \
  '["Gharib89/skills#682"]' "$(jq -c '[.unpushed[].key]' <<<"$out")"
check "its row joins the actions with semicolons" \
  "Needs you (2): [skills#681]($u/issues/681) pick backfill or forward-only; [skills#682]($u/issues/682) approve the held merge" \
  "$(jq -r '.block | split("\n")[0]' <<<"$out")"
L unneed Gharib89/skills#681 >/dev/null; L unneed Gharib89/skills#682 >/dev/null
out=$(S)
check "clearing the needs drops the row and reports the change" "true $(grep -c '^Needs' <<<"$(jq -r .block <<<"$out")")" "$(jq -r '.changed' <<<"$out") 0"

# --- a ledger status never reads GitHub, and a settled triage entry is no merge -
add 800; L set Gharib89/skills#800 kind '"triage"' >/dev/null; stage 800 settled
check "a settled triage entry is in no row" 0 "$(S --digest | jq -r .block | grep -c '#800')"

finish
