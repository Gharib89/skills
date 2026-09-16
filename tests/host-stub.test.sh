#!/usr/bin/env bash
# The stub host CLIs `tests/run.sh` puts in front of every test file. Their job
# is to turn a test that reaches a host from a silent pass into a named failure,
# so the "none of these reaches a host" premise is enforced rather than asserted.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/host-stub.sh

d=$(mktemp -d) || exit 2
trap 'rm -rf "$d"' EXIT
ship_test_host_stub "$d"
export SHIP_TEST_HOSTLOG="$d/calls"

for cli in gh az; do
  : > "$SHIP_TEST_HOSTLOG"
  out=$("$d/$cli" api repos/o/r --jq .x 2>&1); rc=$?
  check_rc "the stub $cli fails rather than reaching a host" 127 "$rc"
  check "the stub $cli records the call it refused" \
    "$cli api repos/o/r --jq .x" "$(cat "$SHIP_TEST_HOSTLOG")"
  check "the stub $cli says nothing on stdout, so a caller reading it gets no answer to mistake for one" \
    '' "$out"
done

# One line per call, so the gate's report names every host the file reached and
# not just the first.
: > "$SHIP_TEST_HOSTLOG"
"$d/gh" pr view 1 >/dev/null 2>&1
"$d/az" repos pr show >/dev/null 2>&1
check "each refused call is its own line" \
  'gh pr view 1
az repos pr show' "$(cat "$SHIP_TEST_HOSTLOG")"

finish
