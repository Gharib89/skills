#!/usr/bin/env bash
# read-pr's argument guard: what a bare invocation answers, and what it says
# about a second positional. Every case here is malformed, so the guard answers
# before `ship_load_host` and nothing reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/read-pr.sh
usage='usage: read-pr <pr>'

err() { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()  { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

check "the usage line names the PR argument" "$usage" "$(err)"
check_rc "a bare invocation is tooling" 2 "$(rc)"

check "an empty PR argument is the usage error" "$usage" "$(err '')"
check_rc "an empty PR argument is tooling" 2 "$(rc '')"

# read-pr takes no flags, so anything after the PR number is unknown.
check "a second positional is named" 'unknown flag: --body' "$(err 1 --body)"
check_rc "a second positional is tooling" 2 "$(rc 1 --body)"

finish
