#!/usr/bin/env bash
# read-pr driven end to end over the Host fake (tests/host-fake.sh): a
# throwaway repo whose origin names GitHub so host detection still runs, and
# SHIP_HOST_ADAPTER points ship_load_host at the fake instead of host/github.sh.
# The subject is the mechanic's own envelope: the PR object unchanged, and a
# host that cannot answer at all reading as tooling (exit 2), not a verdict.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/read-pr.sh
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
check_rc "a read that lands exits 0" 0 "$rc"
check "the PR object comes back unchanged" 'fix: a fake PR' "$(jq -r .title <<<"$out")"
check "the call the mechanic hands the host" $'host_pr_get\t7' "$(cat "$SHIP_FAKE/calls")"

reset
: > "$SHIP_FAKE/host_pr_get.1.fail"
out=$(run 7); rc=$?
check_rc "a read the host cannot answer is tooling, not a verdict" 2 "$rc"
check "and it names the PR it could not read" 'cannot read PR 7' "$(jq -r .error <<<"$out")"

finish
