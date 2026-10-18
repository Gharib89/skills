#!/usr/bin/env bash
# scripts/shell-turn-tests.sh: the turn rung's shell row. The subject is the
# edited-file to test-file mapping (`--list`) and that the selection reaches
# tests/run.sh, which keeps the host stub in front of PATH.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

sel() { bash scripts/shell-turn-tests.sh --list "$@" 2>&1; }
naming() { grep -lF "$1" tests/*.test.sh | sort; }

check "an edited test selects itself only" \
  "tests/token-limit.test.sh" "$(sel tests/token-limit.test.sh)"
check "a script selects the tests naming its basename" \
  "$(naming token-limit-check.sh)" "$(sel scripts/token-limit-check.sh)"
check "an edited test beside a script is not widened by the script's name" \
  "$(printf 'tests/token-limit.test.sh\n%s' "$(naming token-limit-check.sh)" | sort -u)" \
  "$(sel tests/token-limit.test.sh scripts/token-limit-check.sh)"
check "a lib piece selects the tests naming _lib.sh" \
  "$(naming _lib.sh)" "$(sel skills/ship/scripts/lib/"$(ls skills/ship/scripts/lib | head -1)")"
check "_lib.sh selects the tests naming _lib.sh" \
  "$(naming _lib.sh)" "$(sel skills/ship/scripts/_lib.sh)"
# The oracle above repeats the selector's grep, so an empty answer on both sides
# would pass; these two fix the answer.
check "_lib.sh is named by tests, so the selection is not vacuous" 1 \
  "$([ -n "$(naming _lib.sh)" ] && echo 1 || echo 0)"
check "the runner's excluded prefixes select nothing through the turn rung" \
  '{"rung":"turn","verdict":"skipped","checks":{"turn":"skipped"}}' \
  "$(scripts/check.sh turn tests/fixtures/x.sh .claude/skills/ship/scripts/_lib.sh)"
# Built at run time: spelled out here, this file would name it and select itself.
unnamed=zz-unnamed-$$.sh
check "a file no test names selects nothing" "" "$(sel scripts/$unnamed)"
check_rc "a file no test names is no failure" 0 "$(bash scripts/shell-turn-tests.sh scripts/$unnamed >/dev/null 2>&1; echo $?)"

# Only the runner's own lines: a selected test may print a `skipped` line of its
# own (token-limit does without prek), which is no part of the claim.
out=$(bash scripts/shell-turn-tests.sh tests/token-limit.test.sh 2>&1 | grep -E '^(ok|FAIL) |^[0-9]+ passed')
check "the selection runs through the suite runner, one file" \
  "ok   tests/token-limit.test.sh
1 passed, 0 failed" "$out"

# A file reaching a host fails under the runner: the stub is what proves it.
fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
printf '#!/usr/bin/env bash\ngh pr list >/dev/null 2>&1\nexit 0\n' > "$fixture/calls-gh.test.sh"
check_rc "run.sh given a file runs it and the host stub still fails a gh call" 1 \
  "$(bash tests/run.sh "$fixture/calls-gh.test.sh" >/dev/null 2>&1; echo $?)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/clean.test.sh"
check "run.sh given a file runs only that file" \
  "ok   $fixture/clean.test.sh
1 passed, 0 failed" "$(bash tests/run.sh "$fixture/clean.test.sh" 2>&1)"

finish
