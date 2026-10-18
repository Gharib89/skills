#!/usr/bin/env bash
# Phase 9 names the relative merge.sh invocation: auto mode admits the relative
# path an allow rule can match and refuses the absolute base-directory one, so
# the prose must name the form before a run writes the call.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

rel='.claude/skills/ship/scripts/merge.sh'
flat() { tr '\n' ' ' | tr -s ' '; }
step=$(awk '/^## Phase 9 merge gate/{f=1;next} /^## /{f=0} f' skills/ship/reference/phase-steps.md | flat)
setup=$(flat < skills/setup-skills/SKILL.md)
# Each predicate anchors on the sentence's opening words, so a negated sentence
# fails it on the negation, not on letter case.
names_relative() { grep -qF "\`head_sha\`. Invoke it from the worktree root as \`$rel\` where Ship is installed at project scope" <<<"$1"; }
confines_absolute() { grep -qF 'the absolute base-directory path is for an install with no project copy' <<<"$1"; }
names_allow_rule() { grep -qF "so tell them to add \`Bash($rel:*)\` under \`permissions.allow\`" <<<"$1"; }
yn() { "$@" && echo yes || echo no; }

check "phase 9 merge step names the relative merge.sh" yes "$(yn names_relative "$step")"
check "phase 9 merge step confines the absolute form to an install with no project copy" yes \
  "$(yn confines_absolute "$step")"
check "setup-skills tells a consumer to allow the relative merge.sh" yes "$(yn names_allow_rule "$setup")"

# Negated fixtures: the same assertions fail on the sentences with their meaning reversed.
check "negated: never invoke the relative path" no \
  "$(yn names_relative "\`head_sha\`. Never invoke it from the worktree root as \`$rel\` where Ship is installed at project scope")"
check "negated: absolute form for every install" no \
  "$(yn confines_absolute 'the absolute base-directory path is for every install')"
check "negated: do not add the allow rule" no \
  "$(yn names_allow_rule "so do not add \`Bash($rel:*)\` under \`permissions.allow\`")"
finish
