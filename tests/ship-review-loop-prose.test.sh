#!/usr/bin/env bash
# Ship's review loop and turn discipline are prose a run follows without a
# mechanic behind them (#938), so each rule is pinned by the clause that states
# it, read from one line so a wrapped clause still matches. Each clause is also
# run against the same sentence with its meaning negated, which the matcher must
# reject.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

flat() { tr '\n' ' ' | tr -s ' '; }
has() { grep -qiF -- "$2" <<<"$1" && echo yes || echo no; }
loop=$(awk '/^## A window that closes with no round/{f=1; next} /^## /{f=0} f' skills/ship/reference/review-loop.md | flat)
skill=$(flat < skills/ship/SKILL.md)
steps=$(awk '/^## Phase 7 reviewers/{f=1; next} /^## /{f=0} f' skills/ship/reference/phase-steps.md | flat)

check 'the review loop has the section' yes "$([ -n "$loop" ] && echo yes || echo no)"

# <case>|<text read>|<clause it must hold>|<the clause with its meaning negated>
rules=(
  "a closed window with not_reviewed set is the round's answer|loop|A window that closes with \`done: false\` and \`not_reviewed\` set is that round's answer|A window that closes with \`done: false\` and \`not_reviewed\` set is not that round's answer"
  "no second window opens for the same round|loop|no second window opens for the same round|a second window opens for the same round"
  "a pending answer is no closed window|loop|A \`status: pending\` answer is no closed window|A \`status: pending\` answer is a closed window"
  "the stale-head re-poll needs no landed round|loop|bar \`unreachable\` with \`landed_by\` null on a \`head_sha\`|bar \`unreachable\` on a \`head_sha\`"
  "a round after a tree-changing fix stops not landed|loop|\`Stop: <reviewer>: not landed\`|\`Stop: <reviewer>: tree unchanged\`"
  "the stop is final|loop|that exit is final|that exit is not final"
  "the fallback that names it is driven per Fallbacks|loop|reviewer that names it, if any, is driven per [Fallbacks](#fallbacks)|reviewer that names it, if any, is not driven per [Fallbacks](#fallbacks)"
  "phase 7 points at the section|steps|A window that closes with no round|A window that closes with a round"
  "a turn never ends on a plan line|skill|A turn never ends on a plan line|A turn may end on a plan line"
  "a background job's end is announced in one line|skill|announce its end in one line|announce its end in a paragraph"
)
for r in "${rules[@]}"; do
  IFS='|' read -r name where clause negated <<<"$r"
  case $where in loop) text=$loop ;; skill) text=$skill ;; steps) text=$steps ;; esac
  check "$name" yes "$(has "$text" "$clause")"
  check "$name: the negated clause is refused" no "$(has "$negated" "$clause")"
done
finish
