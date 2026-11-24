#!/usr/bin/env bash
# ship_poll_read's bound (#1346, #1409): a read that outlasts SHIP_READ_LIMIT is
# cut off (exit 4) every time, whatever its children do when signalled, and what
# it wrote is no answer. The watchdog ends the read's children before the read, so
# a host function that carries on after its child dies (the Host fake's `sleep`,
# then the answer) could write a full answer and exit 0 before its own TERM
# landed, and ci-wait graded a read past its bound.
#
# The slow read here traps TERM, which makes that outcome certain rather than a
# race: its `sleep` dies of the watchdog's first signal and the function goes on
# to answer and exit 0.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship-run/scripts/_lib.sh

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export SHIP_HTTP_STATUS_FILE=$work/status
out=$work/out

slow_survivor() { trap ':' TERM; sleep 5; echo answered; }
quick() { echo answered; }

SHIP_READ_LIMIT=1 ship_poll_read "$out" slow_survivor; rc=$?
check_rc "a read that survives its child's death is still cut off" 4 "$rc"
check "and its answer is not left for the caller" "" "$(cat "$out")"

SHIP_READ_LIMIT=5 ship_poll_read "$out" quick; rc=$?
check_rc "a read inside its limit is answered" 0 "$rc"
check "and its answer is kept" answered "$(cat "$out")"

# The caller's EXIT trap is lifted while the read forks, and is back after.
SHIP_READ_LIMIT=5
( trap 'echo cleanup' EXIT; ship_poll_read "$out" quick; trap -p EXIT ) > "$work/trap.out"
check "the caller's EXIT trap survives the call" "trap -- 'echo cleanup' EXIT" "$(head -1 "$work/trap.out")"
check "and the call leaves no mark or saved trap beside the out-file" "" "$(compgen -G "$work/*.cut"; compgen -G "$work/*.trap")"

finish
