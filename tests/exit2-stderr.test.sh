#!/usr/bin/env bash
# Every exit-2 path says its reason on stderr as well as in the JSON on stdout,
# the way ship_fail does for exit 1: a caller piping stdout through
# `jq -r .field` reads a malformed call as `null` and exit 0, and stderr is what
# still shows it. Covered: ship_tooling (a malformed call), and the two
# mechanics that exit 2 on a verdict of their own (preflight's host-unreachable
# and tooling's missing CLI).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
export GIT_ALLOW_PROTOCOL=file
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
mech() { local m=$1; shift; ( cd "$repo" && bash "$scripts/$m.sh" "$@" ) 2>"$work/err"; }

out=$(mech read-pr abc); rc=$?
check_rc "a malformed call exits 2" 2 "$rc"
check "its stderr is the usage line stdout carries as .error" "$(jq -r .error <<<"$out")" "$(cat "$work/err")"
check "and is not empty" true "$([ -s "$work/err" ] && echo true || echo false)"

out=$(mech base-fresh extra); rc=$?
check "a tooling error from a guard says it on stderr" "base-fresh takes no arguments" "$(cat "$work/err")"

printf 'me\n'    > "$SHIP_FAKE/host_identity.1.json"
printf 'false\n' > "$SHIP_FAKE/host_can_push.1.json"
out=$(mech preflight none); rc=$?
check_rc "preflight host-unreachable exits 2" 2 "$rc"
check "and says why on stderr" "host-unreachable: me cannot push to owner/repo; switch to the account with access" "$(cat "$work/err")"

rm -f "$SHIP_FAKE"/*
printf 'gh is not installed\n' > "$SHIP_FAKE/host_tooling_reasons.1.json"
out=$(mech tooling); rc=$?
check_rc "tooling with a missing CLI exits 2" 2 "$rc"
check "and names it on stderr" "host-unreachable: gh is not installed" "$(cat "$work/err")"

finish
