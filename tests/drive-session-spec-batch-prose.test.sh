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

check "a slice whose criteria require a timing series is named" yes "$(has 'require a timing series')"
check "that slice also runs alone" yes "$(has 'median and range) also runs alone')"
check "no gate-running triage tab spawns beside it" yes "$(has 'no triage tab that runs the local gate')"
check "the launch turn's slot plan names each run-alone timing slice with its reason" yes "$(has 'names each run-alone timing slice with its reason')"
check "the pre-spawn check lists PRs merged since the brief" yes "$(has 'PRs merged to main since')"
check "the spawn prompt carries the re-check line on an overlap" yes "$(has 're-check the brief against main')"

finish
