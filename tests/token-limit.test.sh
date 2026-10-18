#!/usr/bin/env bash
# scripts/token-limit-check.sh: the 5,000-token file limit at the commit rung.
# Cases drive the script by its command line with real files of chosen sizes in
# a temp dir, as pre-commit calls it; the last cases run the real hook through
# prek in a throwaway repo to prove the exclusions. Without prek, those are skipped.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
# <path> <bytes>: a file of exactly that many bytes.
sized() { mkdir -p "$(dirname "$1")"; head -c "$2" /dev/zero | tr '\0' 'a' > "$1"; }
run() { out=$(bash scripts/token-limit-check.sh "$@" 2>&1); rc=$?; }
# <case> <needle>: the output holds the needle.
says() { case $out in *"$2"*) check "$1" 0 0 ;; *) check "$1" "output holds: $2" "$out" ;; esac; }

sized "$fixture/at.txt" 20000
run "$fixture/at.txt"
check_rc "a file of exactly 20,000 bytes passes" 0 "$rc"

sized "$fixture/over.txt" 20001
run "$fixture/over.txt"
check_rc "a file of 20,001 bytes fails" 1 "$rc"
says "and the message names the file, its token count and the limit" \
  "$fixture/over.txt: 5001 tokens, over the 5000-token limit"

sized "$fixture/a.txt" 24000; sized "$fixture/b.txt" 40000; sized "$fixture/ok.txt" 100
run "$fixture/a.txt" "$fixture/ok.txt" "$fixture/b.txt"
check_rc "several oversize files fail" 1 "$rc"
says "the first oversize file is reported" "a.txt: 6000 tokens"
says "the second oversize file is reported" "b.txt: 10000 tokens"
case $out in *ok.txt*) check "an in-limit file is not reported" 0 1 ;; esac

run
check_rc "no file arguments exits 0" 0 "$rc"

run "$fixture/missing.txt"
check_rc "a missing file exits 2" 2 "$rc"

# <case> <path> <needle>: an oversize file of that path gets that instruction.
kind() {
  sized "$fixture/k/$2" 20001
  run "$fixture/k/$2"
  says "$1" "$3"
}
kind "a shell script gets the lib/ and .d/ instruction" scripts/tool.sh "sibling files the script sources"
kind "a shell test gets the behaviour split instruction" tests/tool.test.sh "split it by behaviour into new tests/*.test.sh"
kind "a SKILL.md gets the reference/ instruction" skills/x/SKILL.md "reference/ folder"
kind "other Markdown gets the section split instruction" docs/note.md "by top-level section"
kind "a JavaScript module gets the export extraction instruction" lib/mod.mjs "extract cohesive exports"
kind "an HTML page gets the style and script instruction" page/board.html "style and script blocks"
kind "an unknown kind gets the generic instruction" data/blob.bin "Split it into smaller files"
kind "a shell script ends with the no-bypass reminder" scripts/tool.sh "do not bypass with \`--no-verify\`"
says "and the no-minify reminder" "do not minify or strip comments to fit"
says "and the stage reminder" "stage the new files"
case $out in *"Split it into smaller files"*) check "a known kind does not get the generic instruction" 0 1 ;; esac

# The exclusions are the hook's `exclude`: run the real hook in a throwaway repo.
if ! command -v prek >/dev/null; then
  skipped "the exclusion cases: prek is not on PATH"
  finish
fi
r=$fixture/repo
mkdir -p "$r/scripts"
cp scripts/token-limit-check.sh "$r/scripts/"
cp .pre-commit-config.yaml "$r/"
git -C "$r" init -q
sized "$r/skills-lock.json" 30000; sized "$r/uv.lock" 30000
sized "$r/pkg/CHANGELOG.md" 30000; sized "$r/CHANGELOG.md" 30000
sized "$r/big.md" 30000
git -C "$r" add -A
hook() { (cd "$r" && prek run token-limit --files "$@" >/dev/null 2>&1); printf '%s' "$?"; }
check_rc "a staged oversize lockfile and CHANGELOG.md do not trip the hook" 0 \
  "$(hook skills-lock.json uv.lock pkg/CHANGELOG.md CHANGELOG.md)"
check_rc "a staged oversize Markdown file trips the hook" 1 "$(hook big.md)"

finish
