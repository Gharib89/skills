#!/usr/bin/env bash
# The token limit on an HTML file at the edit rung. The subject is this repo's
# own scripts/check.sh and .pre-commit-config.yaml, copied into a throwaway git
# repo beside the real scripts/token-limit-check.sh: an HTML file over the limit
# fails `check.sh edit` naming the limit, where `*.html` outside the edit globs
# reported `skipped` and the file was caught only at commit. Without prek on
# PATH, no case runs.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

if ! command -v prek >/dev/null; then
  skipped "token limit at the edit rung: prek is not on PATH"
  finish
fi

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
r=$fixture/repo
mkdir -p "$r/scripts" "$r/docs"
cp scripts/check.sh scripts/prose-budget-check.sh scripts/token-limit-check.sh "$r/scripts/"
cp .pre-commit-config.yaml "$r/"
git -C "$r" init -q

# <bytes>: an HTML page of about that many bytes.
page() { awk -v n="$1" 'BEGIN { print "<p>"; for (i = 0; i < n / 8; i++) print "<b>x</b>"; print "</p>" }'; }
# <file>: run the edit rung on it; leaves the exit code in `rc` and its output in `out`.
edit() {
  out=$(cd "$r" && CLAUDE_CODE_REMOTE='' bash scripts/check.sh edit "$1" 2>&1); rc=$?
}

page 24000 > "$r/docs/big.html"
edit docs/big.html
check_rc "an HTML file over the token limit fails the edit rung" 1 "$rc"
case $out in
  *"docs/big.html: "*" tokens, over the 5000-token limit"*) check "and the failure names the limit" 0 0 ;;
  *) check "and the failure names the limit" "output holds: over the 5000-token limit" "$out" ;;
esac

page 8000 > "$r/docs/small.html"
edit docs/small.html
check_rc "an HTML file inside the limit passes" 0 "$rc"
# Exit 0 is also `skipped`, so the verdict tells a pass from a file the rung never read.
case $out in
  *'"verdict":"pass"'*) check "and the rung read it" 0 0 ;;
  *) check "and the rung read it" 'output holds: "verdict":"pass"' "$out" ;;
esac

finish
