#!/usr/bin/env bash
# The prose budget at the edit rung. The subject is this repo's own
# scripts/check.sh and .pre-commit-config.yaml, copied into a throwaway git repo
# beside the real scripts/prose-budget-check.sh: an edit to a skill's SKILL.md
# or reference file that breaks the budget fails `check.sh edit` with the count
# and the budget, where it used to fail only at the local gate. A stub
# house-style check that always fails proves a Markdown edit does not pay it.
# Without prek on PATH, no case runs.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

if ! command -v prek >/dev/null; then
  skipped "prose budget at the edit rung: prek is not on PATH"
  finish
fi

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
r=$fixture/repo
mkdir -p "$r/scripts" "$r/skills/demo/reference" "$r/docs"
cp scripts/check.sh scripts/prose-budget-check.sh "$r/scripts/"
cp .pre-commit-config.yaml "$r/"
printf '#!/bin/sh\necho "house-style ran"; exit 1\n' > "$r/scripts/house-style-check.sh"
chmod +x "$r/scripts/house-style-check.sh"
git -C "$r" init -q

# <n>: n words on one line.
words() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) printf "w "; print "" }'; }
# <n>: n lines.
lines() { awk -v n="$1" 'BEGIN { for (i = 0; i < n; i++) print "line " i }'; }
# <file>: run the edit rung on it; leaves the exit code in `rc` and stderr in `err`.
edit() {
  err=$(cd "$r" && CLAUDE_CODE_REMOTE='' bash scripts/check.sh edit "$1" 2>&1 >/dev/null); rc=$?
}
# <case> <needle>: stderr names the count and the budget.
says() { case $err in *"$2"*) check "$1" 0 0 ;; *) check "$1" "stderr holds: $2" "$err" ;; esac; }

words 3600 > "$r/skills/demo/SKILL.md"
edit skills/demo/SKILL.md
check_rc "a SKILL.md over its word budget fails the edit rung" 1 "$rc"
says "and the failure names the count and the budget" \
  "skills/demo/SKILL.md: 3600 words, over the 3500-word budget"

words 3400 > "$r/skills/demo/SKILL.md"
edit skills/demo/SKILL.md
check_rc "a SKILL.md within its budget passes" 0 "$rc"

lines 120 > "$r/skills/demo/reference/long.md"
edit skills/demo/reference/long.md
check_rc "a long reference with no ## Contents fails the edit rung" 1 "$rc"
says "and the failure names its line count" \
  "skills/demo/reference/long.md: 120 lines and no \`## Contents\` heading"

{ printf '## Contents\n\n- [Part](#part)\n\n## Part\n'
  lines 120; } > "$r/skills/demo/reference/long.md"
edit skills/demo/reference/long.md
check_rc "a long reference with its map passes" 0 "$rc"

# Markdown outside skills/ pays no house-style on an edit: the stub would fail it.
words 10 > "$r/docs/note.md"
edit docs/note.md
check_rc "an edit to other Markdown runs no house-style" 0 "$rc"

finish
