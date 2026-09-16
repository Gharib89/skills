#!/usr/bin/env bash
# Run every tests/*.test.sh from the repo root. A test file is a standalone bash
# script: it sources the function under test and asserts on strings, runs a gate
# script against a fixture and asserts on its exit code, or invokes a mechanic
# malformed and asserts on the usage error its guard prints. None reaches a host,
# and `tests/host-stub.sh` is what holds them to it: a `gh` and an `az` that record
# the call and fail sit in front of PATH, and a file whose run leaves entries in
# the log fails here whatever its own cases said. The local gate's `tests` gate is
# this script.
#
#   tests/run.sh
#
# stdout: one line per test file, then a count
# stderr: each failing case, named, from the test file itself
# exit: 0 every case passed · 1 a case failed · 2 no test files found
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

shopt -s nullglob
files=(tests/*.test.sh)
[ "${#files[@]}" -gt 0 ] || { echo "no test files under tests/" >&2; exit 2; }

source tests/host-stub.sh
stub=$(mktemp -d) || exit 2
trap 'rm -rf "$stub"' EXIT
ship_test_host_stub "$stub" || exit 2
# In front of PATH, so a test reaching for `gh` or `az` finds the stub. A test
# needing one to answer prepends its own fake, later and therefore earlier.
export SHIP_TEST_HOSTLOG="$stub/calls" PATH="$stub:$PATH"

pass=0 fail=0
for t in "${files[@]}"; do
  : > "$SHIP_TEST_HOSTLOG"
  bash "$t"; rc=$?
  # Read per file, not once at the end, so the report names the file that made
  # the call rather than the suite that contains it.
  if [ -s "$SHIP_TEST_HOSTLOG" ]; then
    rc=1
    { printf 'FAIL %s: reached a host; no test here may:\n' "$t"
      sed 's/^/    /' "$SHIP_TEST_HOSTLOG"
    } >&2
  fi
  if [ "$rc" -eq 0 ]; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$t"
  else
    fail=$((fail + 1)); printf 'FAIL %s\n' "$t"
  fi
done
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
