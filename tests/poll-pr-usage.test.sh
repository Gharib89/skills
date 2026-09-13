#!/usr/bin/env bash
# poll-pr's flag guard: what its usage line offers, and what a flag given no
# value answers. Every case here is malformed, so the guard answers before
# `ship_load_host` and nothing reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/poll-pr.sh
usage='usage: poll-pr <pr> [--await-review <login>] [--since <iso>] [--full <id>[,<id>]] [--timeout <s>] [--interval <s>]'

err() { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()  { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

check "the usage line offers --full" "$usage" "$(err)"

check "--full with no value is the usage error" "$usage" "$(err 1 --full)"
check_rc "--full with no value is tooling" 2 "$(rc 1 --full)"

check "an unknown flag is still named" 'unknown flag: --whole' "$(err 1 --whole 7)"

finish
