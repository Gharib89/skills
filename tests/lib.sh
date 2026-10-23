#!/usr/bin/env bash
# Assertions for the repo's unit tests. Sourced by every tests/*.test.sh.
#
#   source tests/lib.sh
#   check     "<case>" "<expected>" "<actual>"
#   check_rc  "<case>" <expected-rc> <actual-rc>
#   skipped   "<case>"           # a case this runner cannot prove, named on stdout
#   finish                      # exits 0 all cases passed, 1 otherwise
#   ceiling_copy <dir> <since> <s>  # a copy of ship's scripts whose poll-pr
#                                   # ceiling ends <s> seconds after the call
#
# A failing case prints its name and a diff on stderr, so `tests/run.sh` and
# the local gate report which assertion broke rather than that something did.
# Nothing is printed for a passing case: the gate's log is evidence, not noise.
TEST_NAME=$(basename "${BASH_SOURCE[1]:-$0}" .test.sh)
# The stop hook runs the turn rung under a CHECK_DEADLINE that a test inherits,
# and a nested `scripts/check.sh` would answer over-budget once it passes. A
# case that wants a deadline sets its own, inline.
unset CHECK_DEADLINE
_failed=0

check() { # <case> <expected> <actual>
  [ "$2" = "$3" ] && return 0
  _failed=1
  { printf 'FAIL %s: %s\n' "$TEST_NAME" "$1"
    diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/    /'
  } >&2
}

check_rc() { # <case> <expected-rc> <actual-rc>
  [ "$2" = "$3" ] && return 0
  _failed=1
  printf 'FAIL %s: %s (expected exit %s, got %s)\n' "$TEST_NAME" "$1" "$2" "$3" >&2
}

skipped() { printf 'skipped %s: %s\n' "$TEST_NAME" "$1"; }

finish() { exit "$_failed"; }

# poll-pr's ceiling counts from the request (#952), and a fixture dates its
# request in the past, so a case that holds a window runs a copy of ship's
# scripts whose ceiling is the request's age plus the seconds it allows.
ceiling_copy() { # <dir> <since> <seconds past the call>
  cp -R skills/ship/scripts "$1"
  sed -i.bak "s/^ceiling=1800\$/ceiling=\$((\$(date +%s) - $(jq -rn --arg s "$2" '$s | fromdateiso8601') + $3))/" \
    "$1/poll-pr.sh"
}
