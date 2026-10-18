#!/usr/bin/env bash
# drive-session's Spec batch section carries two rules a supervisor follows from
# prose alone, so each is pinned by the phrase that states it: a timing slice runs
# alone (and the launch turn's slot plan names it), and a stale agent brief is
# flagged before its slice spawns.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

section=$(awk '/^## Spec batch/{f=1; next} /^## /{f=0} f' skills/drive-session/SKILL.md | tr '\n' ' ' | tr -s ' ')
has() { grep -qiF -- "$1" <<<"$section" && echo yes || echo no; }

check "timing slices run alone" yes "$(has 'require a timing series')"
check "no gate-running triage tab spawns during the series" yes "$(has 'no triage tab that runs a gate')"
check "the slot plan names each run-alone slice and why" yes "$(has 'names each run-alone timing slice')"
check "the pre-spawn check lists PRs merged since the brief" yes "$(has 'PRs merged to main since')"
check "the spawn prompt carries the re-check line on an overlap" yes "$(has 're-check the brief against main')"

finish
