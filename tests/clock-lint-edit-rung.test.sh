#!/usr/bin/env bash
# The clock lint at the edit rung and in `full`. The subject is this repo's own
# scripts/check.sh and .pre-commit-config.yaml, copied into a throwaway git repo
# beside the real scripts/clock-lint.sh: an edited test file that reads the clock
# fails `check.sh edit`. The `full` row is read out of check.sh's configuration.
# Without prek on PATH, the edit cases do not run.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

check "full runs the clock lint as its own row" 1 \
  "$(grep -c '^clock|scripts/clock-lint.sh$' scripts/check.sh)"

if ! command -v prek >/dev/null; then
  skipped "clock lint at the edit rung: prek is not on PATH"
  finish
fi

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
r=$fixture/repo
mkdir -p "$r/scripts" "$r/tests"
cp scripts/check.sh scripts/clock-lint.sh scripts/token-limit-check.sh "$r/scripts/"
cp .pre-commit-config.yaml "$r/"
git -C "$r" init -q

# <file>: run the edit rung on it; leaves the exit code in `rc` and its output in `out`.
edit() {
  out=$(cd "$r" && CLAUDE_CODE_REMOTE='' bash scripts/check.sh edit "$1" 2>&1); rc=$?
}

printf '#!/usr/bin/env bash\ndate +%%s\n' > "$r/tests/reads.test.sh"
edit tests/reads.test.sh
check_rc "a test file reading the clock fails the edit rung" 1 "$rc"
case $out in *"reads the current time"*) check "and the failure names the rule" 0 0 ;; *) check "and the failure names the rule" "output holds the rule" "$out" ;; esac

printf '#!/usr/bin/env bash\ndate -u -d @1800000000 +%%s\n' > "$r/tests/fixed.test.sh"
edit tests/fixed.test.sh
check_rc "a test file converting a fixed time passes" 0 "$rc"
# Exit 0 is also `skipped`, so the verdict tells a pass from a file the rung never read.
case $out in *'"verdict":"pass"'*) check "and the rung read it" 0 0 ;; *) check "and the rung read it" 'verdict pass' "$out" ;; esac

finish
