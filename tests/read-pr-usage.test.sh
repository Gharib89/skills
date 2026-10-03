#!/usr/bin/env bash
# read-pr's guard on a second positional. The PR slot itself is `ship_args`'s,
# tested in ship-args.test.sh. Every case here is malformed, so the guard
# answers before `ship_load_host` and nothing reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/read-pr.sh

err() { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()  { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

# read-pr takes no flags, so anything after the PR number is unknown.
check "a second positional is named" 'unknown flag: --body' "$(err 1 --body)"
check_rc "a second positional is tooling" 2 "$(rc 1 --body)"

finish
