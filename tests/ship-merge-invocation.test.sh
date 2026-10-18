#!/usr/bin/env bash
# Phase 9 names the relative merge.sh invocation: auto mode admits the relative
# path an allow rule can match and refuses the absolute base-directory one, so
# the prose must name the form before a run writes the call.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

rel='.claude/skills/ship/scripts/merge.sh'
step=$(awk '/^## Phase 9 merge gate/{f=1;next} /^## /{f=0} f' skills/ship/reference/phase-steps.md)

check "phase 9 merge step names the relative merge.sh" yes \
  "$(grep -qF "$rel" <<<"$step" && echo yes || echo no)"
check "phase 9 merge step confines the absolute form to an install with no project copy" yes \
  "$(grep -qi 'no project copy' <<<"$step" && echo yes || echo no)"
check "setup-skills tells a consumer to allow the relative merge.sh" yes \
  "$(grep -qF "Bash($rel:*)" skills/setup-skills/SKILL.md && echo yes || echo no)"
finish
