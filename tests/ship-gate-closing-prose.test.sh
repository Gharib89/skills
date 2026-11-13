#!/usr/bin/env bash
# Ship's merge-gate closing sequence and its stop table are prose a run follows
# without a mechanic behind them (#1211), so each is pinned by the clause that
# states it, read from one line so a wrapped clause still matches. Each clause
# is also run against the same sentence with its meaning negated, which the
# matcher must reject.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

flat() { tr '\n' ' ' | tr -s ' '; }
has() { grep -qiF -- "$2" <<<"$1" && echo yes || echo no; }
gate=$(flat < skills/ship/reference/merge-gate.md)
skill=$(flat < skills/ship/SKILL.md)
isolate=$(flat < skills/ship/reference/isolate.md)

# <case>|<text read>|<clause it must hold>|<the clause with its meaning negated>
rules=(
  "the merge gate leaves the worktree before cleanup removes it|gate|then \`ExitWorktree\` with \`action: \"keep\"\` (\`cleanup\` owns the removal)|then \`ExitWorktree\` with \`action: \"remove\"\` (\`cleanup\` owns the removal)"
  "the stop table names the issue-not-found reason|skill|\`issue #<n> not found or unreadable\`|\`issue #<n> found and readable\`"
  "existing PR is a PR that closes the issue|isolate|\`existing PR\` is a live PR whose body **closes** this issue|\`existing PR\` is a live PR whose body **mentions** this issue"
  "a branch ending in the issue number is existing branch|isolate|a head branch on origin ending in \`-<issue>\` is \`existing branch\`|a head branch on origin ending in \`-<issue>\` is \`existing PR\`"
)
for r in "${rules[@]}"; do
  IFS='|' read -r name where clause negated <<<"$r"
  case $where in gate) text=$gate ;; skill) text=$skill ;; isolate) text=$isolate ;; esac
  check "$name" yes "$(has "$text" "$clause")"
  check "$name: the negated clause is refused" no "$(has "$negated" "$clause")"
done
finish
