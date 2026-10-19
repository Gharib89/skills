#!/usr/bin/env bash
# drive-session's Spec batch section carries two rules a supervisor follows from
# prose alone, so each is pinned by the clause that states it: a timing slice
# runs alone (and the launch turn's slot plan names it), and a stale agent brief
# is flagged before its slice spawns. The merge allowance's reviewer-rule holds
# are pinned the same way, over the merge allowance paragraphs. Each clause is also run against the same
# sentence with its meaning negated, which the matcher must reject.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

# The section on one line, so a clause wrapped across lines still matches.
section=$(awk '/^## Spec batch/{f=1; next} /^## /{f=0} f' skills/drive-session/SKILL.md | tr '\n' ' ' | tr -s ' ')
has() { grep -qiF -- "$2" <<<"$1" && echo yes || echo no; }

# <case>|<clause the section must hold>|<the clause with its meaning negated>
rules=(
  "a timing-series slice also runs alone|require a timing series (repeated A/B runs, a median and range) also runs alone|require a timing series (repeated A/B runs, a median and range) does not run alone"
  "no triage tab that runs the local gate is spawned|no triage tab that runs the local gate is spawned|a triage tab that runs the local gate is spawned"
  "no triage tab that runs the local gate is still running|no triage tab that runs the local gate is still running|a triage tab that runs the local gate may still be running"
  "the launch turn's slot plan names each run-alone timing slice with its reason|names each run-alone timing slice with its reason|names no run-alone timing slice"
  "the pre-spawn check lists the PRs merged since the brief|Before spawning a slice, list the PRs merged to main since|Before spawning a slice, do not list the PRs merged to main since"
  "an overlap adds the re-check line to the spawn prompt|the spawn prompt gains one line telling the run to re-check the brief against main|the spawn prompt gains no line telling the run to re-check the brief against main"
)
for r in "${rules[@]}"; do
  IFS='|' read -r name clause negated <<<"$r"
  check "$name" yes "$(has "$section" "$clause")"
  check "$name: the negated clause is refused" no "$(has "$negated" "$clause")"
done

# The merge allowance paragraphs, which hold the reviewer-rule holds the
# supervisor decides.
allowance=$(awk '/^The \*\*merge allowance\*\*/{f=1} /^## /{f=0} f' skills/drive-session/SKILL.md | tr '\n' ' ' | tr -s ' ')
allow_rules=(
  "the past-cap hold is merged|stopped on \`tree unchanged\`. Answer \`--text merge\`.|stopped on \`tree unchanged\`. Escalate it."
  "a small lane hold asks for one more host round|a host round read an earlier head. Ask the session with \`--text\` for one more host round|a host round read an earlier head. Answer \`--text merge\` at once"
  "a cap hold takes the same extra round|the same one more host round, and the same answer|answer \`--text merge\` with no further host round"
  "other holds and unmet criteria are escalations|any other \`held_by\` entry, and every unmet criterion are escalations|any other \`held_by\` entry, and every unmet criterion are merged"
  "a finished task is read with --rest|read it with \`--rest\`, so|read it without \`--rest\`, so"
)
for r in "${allow_rules[@]}"; do
  IFS='|' read -r name clause negated <<<"$r"
  check "$name" yes "$(has "$allowance" "$clause")"
  check "$name: the negated clause is refused" no "$(has "$negated" "$clause")"
done

finish
