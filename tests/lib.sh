#!/usr/bin/env bash
# Assertions for the repo's unit tests. Sourced by every tests/*.test.sh.
#
#   source tests/lib.sh
#   check     "<case>" "<expected>" "<actual>"
#   check_rc  "<case>" <expected-rc> <actual-rc>
#   finish                      # exits 0 all cases passed, 1 otherwise
#
# A failing case prints its name and a diff on stderr, so `tests/run.sh` and
# the local gate report which assertion broke rather than that something did.
# Nothing is printed for a passing case: the gate's log is evidence, not noise.
TEST_NAME=$(basename "${BASH_SOURCE[1]:-$0}" .test.sh)
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

finish() { exit "$_failed"; }
