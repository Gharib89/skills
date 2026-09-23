#!/usr/bin/env bash
# `request-review`'s usage guard. Every case is answered before `ship_load_host`,
# so no host is reached.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/request-review.sh
u='usage: request-review <pr> --reviewer <name>'

err() { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()  { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

check "the usage line names the reviewer by name" "$u" "$(err)"
check_rc "a bare invocation is tooling" 2 "$(rc)"

check "a missing --reviewer is the usage error" "$u" "$(err 12)"
check "a flag in the pr slot is the usage error" "$u" "$(err --reviewer claude)"

check "--reviewer with no name is the usage error" "$u" "$(err 12 --reviewer)"
check_rc "--reviewer with no name is tooling" 2 "$(rc 12 --reviewer)"
check "--reviewer given a flag as its name is the usage error" "$u" "$(err 12 --reviewer --nope)"

# The positional login and the comment phrase are the block's to answer now.
check "a positional login is an unknown flag" "unknown flag: bot" "$(err 12 bot)"
check "--comment is an unknown flag" "unknown flag: --comment" "$(err 12 --reviewer claude --comment @claude)"
check "an unknown flag names itself" "unknown flag: --nope" "$(err 12 --nope)"
check_rc "an unknown flag is tooling" 2 "$(rc 12 --nope)"

finish
