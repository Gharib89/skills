#!/usr/bin/env bash
# protections (#1103) over the Host fake: the mechanic reads the PR's base
# branch, hands it to the adapter and puts the answer on one summary line. It
# makes no host write and no other call. Unreadable reads `unknown`, never none.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/protections.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
run()   { ( cd "$repo" && bash "$mech" "$@" ); }
reset() { rm -f "$SHIP_FAKE"/*; }

reset
out=$(run 7); rc=$?
check_rc "an unprotected base answers exit 0" 0 "$rc"
check "the line says Ship's controls are the only ones" \
  "Host protections on main: protected no (Ship's own controls are the only merge controls)" "$(jq -r .line <<<"$out")"
check "only the PR read and the one protections read reach the host, no write" \
  $'host_pr_get\t7\nhost_branch_protections\tmain' "$(cat "$SHIP_FAKE/calls")"

reset
jq -n '{branch:"main",protected:"yes",required_checks:["a","b"],required_reviews:1,bypass:"yes"}' > "$SHIP_FAKE/host_branch_protections.1.json"
check "a protected base lists checks, reviews and bypass" \
  "Host protections on main: protected yes; required checks: a, b; required reviews: 1; admin bypass: yes" "$(run 7 | jq -r .line)"

reset
jq -n '{branch:"main",protected:"unknown",required_checks:"unknown",required_reviews:"unknown",bypass:"unknown"}' > "$SHIP_FAKE/host_branch_protections.1.json"
check "an unreadable answer prints unknown, never none" \
  "Host protections on main: protected unknown; required checks: unknown; required reviews: unknown; admin bypass: unknown" "$(run 7 | jq -r .line)"

reset
: > "$SHIP_FAKE/host_pr_get.1.fail"
out=$(run 7 2>/dev/null); rc=$?
check_rc "a PR that cannot be read is tooling" 2 "$rc"
check "and says so" 'cannot read PR 7' "$(jq -r .error <<<"$out")"

check "a flag after the PR is named" 'unknown flag: --x' "$(run 7 --x 2>/dev/null | jq -r .error)"

finish
