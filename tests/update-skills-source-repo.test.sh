#!/usr/bin/env bash
# update-skills keeps its source-repo-only steps in `reference/source-repo.md`,
# out of the SKILL.md every consumer run reads, and keeps an `## In a Ship run`
# heading in SKILL.md because the upstream-drift workflow names that section in
# every drift issue it files.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

skill=skills/update-skills/SKILL.md
ref=skills/update-skills/reference/source-repo.md

named=$(grep -o 'by the \\"[^\\]*\\" section of update-skills' .github/workflows/upstream-drift.yml | sed 's/^by the \\"//; s/\\".*//')
check "the workflow names a section" "In a Ship run" "$named"
check "SKILL.md carries the section the workflow names" 1 "$(grep -cxF "## $named" "$skill")"
check "the reference exists" yes "$([ -f "$ref" ] && echo yes || echo no)"
check "SKILL.md links the reference's source-repo mode" yes \
  "$(grep -qF '(reference/source-repo.md#source-repo-mode)' "$skill" && echo yes || echo no)"
check "SKILL.md links the reference's Ship-run steps" yes \
  "$(grep -qF '(reference/source-repo.md#in-a-ship-run)' "$skill" && echo yes || echo no)"
for h in '## Source-repo mode' '## In a Ship run'; do
  check "the reference carries $h" 1 "$(grep -cxF "$h" "$ref" 2>/dev/null)"
done
# Phrases only the moved steps use: a copy left behind in SKILL.md is caught.
for p in 'Read what moved' 'held back: <skill>' 'red-after-retry: heads'; do
  check "SKILL.md no longer carries '$p'" 0 "$(grep -cF "$p" "$skill")"
  check "the reference carries '$p'" 1 "$(grep -cF "$p" "$ref" 2>/dev/null)"
done

finish
