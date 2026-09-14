#!/usr/bin/env bash
# `request-review`'s usage guard, including the comment transport's flag. Every
# case is answered before `ship_load_host`, so no host is reached.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/request-review.sh
u='usage: request-review <pr> <login> [--comment <phrase>]'

err() { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()  { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

check "the usage line names the comment transport" "$u" "$(err)"
check_rc "a bare invocation is tooling" 2 "$(rc)"

check "a missing login is the usage error" "$u" "$(err 12)"
check "a flag in the pr slot is the usage error" "$u" "$(err --comment @claude)"
check "a flag in the login slot is the usage error" "$u" "$(err 12 --comment)"

check "--comment with no phrase is the usage error" "$u" "$(err 12 bot --comment)"
check_rc "--comment with no phrase is tooling" 2 "$(rc 12 bot --comment)"

check "an unknown flag names itself" "unknown flag: --nope" "$(err 12 bot --nope)"
check_rc "an unknown flag is tooling" 2 "$(rc 12 bot --nope)"

check "a stray positional names itself" "unknown flag: extra" "$(err 12 bot extra)"

finish
