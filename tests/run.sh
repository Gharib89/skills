#!/usr/bin/env bash
# Run every tests/*.test.sh from the repo root. A test file is a standalone bash
# script: it sources the function under test and asserts on strings, reaching no
# host. The local gate's `tests` gate is this script.
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
[ ${#files[@]} -gt 0 ] || { echo "no test files under tests/" >&2; exit 2; }

pass=0 fail=0
for t in "${files[@]}"; do
  if bash "$t"; then
    pass=$((pass + 1)); printf 'ok   %s\n' "$t"
  else
    fail=$((fail + 1)); printf 'FAIL %s\n' "$t"
  fi
done
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
