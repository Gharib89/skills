#!/usr/bin/env bash
# super-agent's `ledger ruling` scope, driven through its command line: a ruling
# scoped to a repo is kept with its scope on a plain ruling, so the gate-hold
# step-in can cite the one for the run's repo, and `scoped` lists those. A machine
# scope is refused: no step reads it. `--brief` is refused too, and a ledger whose
# rulings carry the old brief mark still reads, lists and applies every one.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
L() { bash "$s/ledger.sh" --ledger "$tmp/ledger.json" "$@"; }

L ruling "Widgets-only ruling." --repo Acme/Widgets >/dev/null
L ruling "Gears ruling." --repo acme/gears --allow "a call" >/dev/null
L ruling "Unscoped ruling." >/dev/null
check "the ledger keeps a ruling's repo as given" '["Acme/Widgets","acme/gears",null]' "$(L list | jq -c '[.rulings[].repo]')"
check "scoped lists only the rulings with a repo, with date, text and repo" '[["Widgets-only ruling.","Acme/Widgets"],["Gears ruling.","acme/gears"]]' \
  "$(L scoped | jq -c '[.scoped[] | [.text, .repo]]')"
check "scoped --repo lists one repo's, compared without regard to case" '["Widgets-only ruling."]' "$(L scoped --repo acme/widgets | jq -c '[.scoped[].text]')"
check_rc "a machine scope exits 2" 2 "$(L ruling x --machine box >/dev/null 2>&1; echo $?)"
check "and names where machine-wide behaviour belongs" 1 "$(L ruling x --machine box 2>/dev/null | jq -r .error | grep -c 'global rules')"

M() { bash "$s/ledger.sh" --ledger "$tmp/m-ledger.json" "$@"; }
# --- the brief-bound mark is gone: refused, and an old mark still reads -----------
out=$(M ruling "reviews are Claude self-review only" --brief 2>/dev/null); rc=$?
check_rc "--brief exits 2" 2 "$rc"
check "and names where such a rule belongs now" "1 1 1" \
  "$(for w in "ship profile" "plain ruling" "global rules"; do jq -r .error <<<"$out" | grep -c "$w"; done | paste -sd' ')"
check "a plain ruling carries no brief or machine key" '["allow","date","expires","pinned","repo","text"]' "$(M ruling plain | jq -c '.ruling | keys')"
old=$tmp/old-ledger.json
export SA_NOW=1762128000 # 2025-11-03: inside the old rulings' 7 days, which ADR 0021 lapses after
printf '%s\n' '{"entries":{},"rulings":[{"date":"2025-11-01","text":"old brief-bound","allow":["a call"],"brief":true,"repo":"acme/widgets","machine":"box"},{"date":"2025-11-02","text":"old plain","allow":[],"brief":false,"repo":null,"machine":null}]}' > "$old"
check "a ledger with the old mark still lists every ruling" '["old brief-bound","old plain"]' "$(bash "$s/ledger.sh" --ledger "$old" list | jq -c '[.rulings[].text]')"
check "and still applies each ruling's allowed call" '["a call"]' "$(bash "$s/ledger.sh" --ledger "$old" allowed | jq -c '[.allowed[].call]')"
check "and lists the one scoped to a repo" '["old brief-bound"]' "$(bash "$s/ledger.sh" --ledger "$old" scoped | jq -c '[.scoped[].text]')"
check "adding to it drops none" 3 "$(bash "$s/ledger.sh" --ledger "$old" ruling new >/dev/null; bash "$s/ledger.sh" --ledger "$old" list | jq '.rulings | length')"

finish
