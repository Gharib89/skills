#!/usr/bin/env bash
# list-prs driven end to end over the Host fake (tests/host-fake.sh): a
# throwaway repo whose origin names GitHub so host detection still runs, and
# SHIP_HOST_ADAPTER points ship_load_host at the fake instead of host/github.sh.
# The subject is the mechanic's own envelope: the count derived from the list,
# and a host that cannot answer reading as tooling (exit 2), not a verdict.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/list-prs.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh

run()   { ( cd "$repo" && bash "$mech" --open ); }
reset() { rm -f "$SHIP_FAKE"/*; }

reset
out=$(run); rc=$?
check_rc "a list that lands exits 0" 0 "$rc"
check "the count matches the list the host answered" '1' "$(jq -r .count <<<"$out")"
check "the call the mechanic hands the host takes no args" 'host_prs_open' \
  "$(cat "$SHIP_FAKE/calls")"

reset
: > "$SHIP_FAKE/host_prs_open.1.fail"
out=$(run); rc=$?
check_rc "a list the host cannot answer is tooling, not a verdict" 2 "$rc"
check "and it names the read that failed" 'cannot list pull requests' \
  "$(jq -r .error <<<"$out")"

finish
