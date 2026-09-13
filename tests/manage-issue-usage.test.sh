#!/usr/bin/env bash
# manage-issue's subcommand guard: which verbs it names, and what it says about
# a verb given too many arguments. Every case here is malformed, so the guard
# answers before `ship_load_host` and nothing reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/manage-issue.sh

err() { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()  { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

check "the usage line names every verb" \
  'usage: manage-issue <issue> take|release|handback "<reason>"|close' \
  "$(err)"
check_rc "a bare invocation is tooling" 2 "$(rc)"

# `manage-issue close` is the verb in the issue position: the issue number is
# missing, so this is the usage error, not an unknown subcommand.
check "a verb with no issue number is the usage error" \
  'usage: manage-issue <issue> take|release|handback "<reason>"|close' \
  "$(err close)"
check_rc "a verb with no issue number is tooling" 2 "$(rc close)"

check "close takes no further argument" \
  'close takes no further argument' \
  "$(err 1 close extra)"
check_rc "close with an extra argument is tooling" 2 "$(rc 1 close extra)"

check "an unknown verb is still named" \
  'unknown subcommand: abandon' \
  "$(err 1 abandon)"

finish
