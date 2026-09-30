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
# Files run concurrently, at most $SHIP_TEST_JOBS at once (default: the CPU
# count), because the suite spends its time waiting on subprocesses, not on the
# CPU. Each file gets a host log and output files of its own, so the host check
# still names the file that made the call, and the report is printed once every
# file has finished, in file order, whichever finished first.
#
#   tests/run.sh
#
# stdout: one line per test file, then a count
# stderr: each failing case, named, from the test file itself
# exit: 0 every case passed · 1 a case failed · 2 no test files found or a bad
#       $SHIP_TEST_JOBS
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

shopt -s nullglob
files=(tests/*.test.sh)
[ "${#files[@]}" -gt 0 ] || { echo "no test files under tests/" >&2; exit 2; }

source tests/host-stub.sh
# `wait -n`, which the worker pool throttles on, arrived in Bash 4.3.
[ "${BASH_VERSINFO[0]}${BASH_VERSINFO[1]}" -ge 43 ] || { echo "tests/run.sh needs Bash 4.3 or newer, got $BASH_VERSION" >&2; exit 2; }
workers=${SHIP_TEST_JOBS:-$(nproc 2>/dev/null || echo 1)}
[[ $workers =~ ^[1-9][0-9]*$ ]] || { echo "SHIP_TEST_JOBS must be a positive integer, got '$workers'" >&2; exit 2; }
stub=$(mktemp -d) || exit 2
trap 'rm -rf "$stub"' EXIT
ship_test_host_stub "$stub" || exit 2
# In front of PATH, so a test reaching for `gh` or `az` finds the stub. A test
# needing one to answer prepends its own fake, later and therefore earlier.
export PATH="$stub:$PATH"

# <n> <file>: one file, its host log and its output kept apart from every other's.
run_one() {
  local n=$1 t=$2
  : > "$stub/log.$n"
  SHIP_TEST_HOSTLOG="$stub/log.$n" bash "$t" > "$stub/out.$n" 2> "$stub/err.$n"
  echo $? > "$stub/rc.$n"
}
for n in "${!files[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$workers" ]; do wait -n; done
  run_one "$n" "${files[n]}" &
done
wait

pass=0 fail=0
for n in "${!files[@]}"; do
  t=${files[n]}
  cat "$stub/out.$n"; cat "$stub/err.$n" >&2
  rc=$(<"$stub/rc.$n")
  # Read per file, not once at the end, so the report names the file that made
  # the call rather than the suite that contains it.
  if [ -s "$stub/log.$n" ]; then
    rc=1
    { printf 'FAIL %s: reached a host; no test here may:\n' "$t"
      sed 's/^/    /' "$stub/log.$n"
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
