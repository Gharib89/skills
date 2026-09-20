#!/usr/bin/env bash
# poll-pr's flag guard: what its usage line offers, and what a flag given no
# value answers. Every case here is malformed, so the guard answers before
# `ship_load_host` and nothing reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/poll-pr.sh
usage='usage: poll-pr <pr> [--brief [--full <id>[,<id>]]] [--await-review <login>] [--since <iso>] [--await-run <workflow-file>, whose run holds the window open past --timeout, to 1800s] [--timeout <s>] [--interval <s>]'

err() { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()  { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

check "the usage line offers --full" "$usage" "$(err)"

# --brief takes no value, so the only way it can be malformed is the missing
# positional every mechanic answers the same way.
check "the usage line offers --brief" "$usage" "$(err --brief)"
check_rc "--brief without a pr is tooling" 2 "$(rc --brief)"

check "--full with no value is the usage error" "$usage" "$(err 1 --full)"
check_rc "--full with no value is tooling" 2 "$(rc 1 --full)"

# Without this guard --full would read --timeout as its id and start a poll.
check "--full given a flag as its value is the usage error" "$usage" "$(err 1 --full --timeout)"
check_rc "--full given a flag as its value is tooling" 2 "$(rc 1 --full --timeout)"

# `--full` names the rows the brief returns whole. Given without `--brief` it
# named rows in the full shape, which already carries every body: a run reading
# `.rounds[0].body` off that answer got null three times in /ship 205, with no
# error to say the pair was wrong. The refusal is the one `--await-run` makes
# against its own pair.
check "--full without --brief is refused" '--full needs --brief' "$(err 1 --full 11)"
check_rc "--full without --brief is tooling" 2 "$(rc 1 --full 11)"
check "an unknown flag is still named" 'unknown flag: --whole' "$(err 1 --whole 7)"

finish
