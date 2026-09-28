#!/usr/bin/env bash
# skills/setup-harness/scripts/check-contract.sh: a repo's check entry point
# held to the contract its callers parse. The subject is the verdict a
# setup-harness re-run reads: exit 0 and the entry point's own line when it
# answers one JSON line whose exit code matches its verdict, exit 1 and one
# line per violation otherwise. Each case is a stub entry point printing a
# fixed answer, the way a hand-edited check.sh can.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
checker=$PWD/skills/setup-harness/scripts/check-contract.sh

# <name> <body>: a stub entry point; prints its path.
entry() { printf '#!/bin/sh\n%s\n' "$2" > "$fixture/$1"; chmod +x "$fixture/$1"; printf '%s' "$fixture/$1"; }
run() { out=$(bash "$checker" "$@" 2>/dev/null); rc=$?; }

run "$(entry pass 'echo "{\"rung\":\"$1\",\"verdict\":\"pass\",\"checks\":{\"lint\":\"pass\"}}"')" full
check_rc "a passing answer holds" 0 "$rc"
check "a held contract prints the entry point's line" '{"rung":"full","verdict":"pass","checks":{"lint":"pass"}}' "$out"

run "$(entry fail 'echo "lint: BAD" >&2; echo "{\"rung\":\"edit\",\"verdict\":\"fail\",\"checks\":{\"lint\":\"fail\",\"fmt\":\"pass\"}}"; exit 1')" edit a.py
check_rc "a failing answer with exit 1 holds: a red check is the repo's code" 0 "$rc"
err=$(bash "$checker" "$fixture/fail" edit a.py 2>&1 >/dev/null)
check "the entry point's stderr passes through, so the failing check's tail reaches the run" "lint: BAD" "$err"

run "$(entry skipped 'echo "{\"rung\":\"edit\",\"verdict\":\"skipped\",\"checks\":{}}"')" edit README
check_rc "a skipped answer with exit 0 and no checks holds" 0 "$rc"

run "$(entry unavailable 'echo "{\"rung\":\"turn\",\"verdict\":\"unavailable\",\"checks\":{\"typecheck\":\"unavailable\"}}"; exit 2')" turn
check_rc "an unavailable answer with exit 2 holds" 0 "$rc"
run "$(entry overbudget 'echo "{\"rung\":\"turn\",\"verdict\":\"over-budget\",\"checks\":{\"tests\":\"over-budget\"}}"; exit 3')" turn
check_rc "an over-budget answer with exit 3 holds" 0 "$rc"
run "$(entry overbudget0 'echo "{\"rung\":\"turn\",\"verdict\":\"over-budget\",\"checks\":{}}"; exit 0')" turn
check "an over-budget answer off exit 3 is named" "exit: verdict over-budget wants 3, got 0" "$out"
run "$(entry unavailable1 'echo "{\"rung\":\"turn\",\"verdict\":\"unavailable\",\"checks\":{}}"; exit 1')" turn
check "an unavailable answer off exit 2 is named" "exit: verdict unavailable wants 2, got 1" "$out"

run "$(entry tooling 'echo "check.sh: not in a git repo" >&2; exit 2')" full
check_rc "no line with exit 2 is the entry point's tooling failing, not a violation" 2 "$rc"
check "a tooling answer prints nothing" "" "$out"

run "$(entry silent 'exit 0')" full
check_rc "no JSON line breaks the contract" 1 "$rc"
check "the missing line is named" "stdout: want one JSON line, got 0 lines" "$out"

run "$(entry chatty 'echo "running lint"; echo "{\"rung\":\"full\",\"verdict\":\"pass\",\"checks\":{}}"')" full
check "a second stdout line is named" "stdout: want one JSON line, got 2 lines" "$out"

run "$(entry notjson 'echo "all good"')" full
check "a line that is not JSON is named" "stdout: not a JSON object: all good" "$out"

run "$(entry array 'echo "[1]"')" full
check "a JSON line that is not an object is named" "stdout: not a JSON object: [1]" "$out"

run "$(entry noverdict 'echo "{\"rung\":\"full\",\"checks\":{}}"')" full
check "a missing verdict is named" "verdict: want pass | fail | unavailable | skipped | over-budget, got nothing" "$out"

run "$(entry rung 'echo "{\"rung\":\"turn\",\"verdict\":\"pass\",\"checks\":{}}"')" full
check "a rung other than the one asked is named" "rung: want full, got turn" "$out"

run "$(entry verdict 'echo "{\"rung\":\"full\",\"verdict\":\"ok\",\"checks\":{}}"')" full
check "a verdict outside the vocabulary is named" \
  "verdict: want pass | fail | unavailable | skipped | over-budget, got ok" "$out"

run "$(entry status 'echo "{\"rung\":\"full\",\"verdict\":\"pass\",\"checks\":{\"lint\":\"green\"}}"')" full
check "a check status outside the vocabulary is named" \
  "checks.lint: want pass | fail | unavailable | skipped | over-budget, got green" "$out"

run "$(entry nochecks 'echo "{\"rung\":\"full\",\"verdict\":\"pass\"}"')" full
check "a missing checks object is named" "checks: want an object of <name>: <status>" "$out"

run "$(entry code 'echo "{\"rung\":\"full\",\"verdict\":\"fail\",\"checks\":{\"lint\":\"fail\"}}"; exit 0')" full
check "an exit code off the verdict is named" "exit: verdict fail wants 1, got 0" "$out"

nopy=$fixture/nopy; mkdir -p "$nopy"
ln -s "$(command -v mktemp)" "$nopy/mktemp"; ln -s "$(command -v rm)" "$nopy/rm"
out=$(PATH=$nopy /bin/bash "$checker" "$fixture/pass" full 2>/dev/null); rc=$?
check_rc "no python3 on PATH is a tooling error" 2 "$rc"

run
check_rc "a bare invocation is a usage error" 2 "$rc"
run "$fixture/absent" full
check_rc "an entry point that cannot run is a tooling error" 2 "$rc"

finish
