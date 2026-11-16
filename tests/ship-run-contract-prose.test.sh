#!/usr/bin/env bash
# Ship's SKILL.md carries the run contract a launch brief repeats (#1266): the
# waiting line, the branch rule, the closing message and the ruling rule. The
# waiting line is the constant the super agent's watcher matches, so the test
# reads it from `sa_waiting_line` in the super agent's _lib.sh and fails when
# SKILL.md carries any other text. Each clause is also run against a changed
# sentence, which the matcher must reject.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

flat() { tr '\n' ' ' | tr -s ' '; }
has() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }
skill=$(flat < skills/ship/SKILL.md)
wl=$(sed -n "s/^sa_waiting_line='\(.*\)'\$/\1/p" skills/super-agent/scripts/_lib.sh)
check "the watcher's waiting line was read from its source" "Waiting on my own background work." "$wl"

# <case>¦<clause SKILL.md must hold>¦<the clause with its meaning changed>
rules=(
  "a turn that only waits ends on the watcher's line, word for word¦ends with this line, word for word, as its last line, without the backticks: \`$wl\`¦ends with this line, word for word, as its last line, without the backticks: \`${wl%.} again.\`"
  "a run that starts in a worktree stays on its branch and makes no other¦A run that starts in a worktree on a branch ending \`-<issue>\` works there, on that branch, and makes no other¦A run that starts in a worktree on a branch ending \`-<issue>\` works there, on a branch of its own"
  "the last message ends on the PR URL and the gate state¦The last message ends on the PR URL and the gate state, or on the stop reason before the gate, never the waiting line¦The last message ends on the waiting line"
  "a ruling after a hold is acted on¦a later message in the thread may carry a ruling on that hold: act on it, not as a new task¦a later message in the thread is a new task"
  "a ruling stays out of the PR body unless it is a waiver that passed the gate¦A ruling never goes into the PR body, except a waiver that passed the gate, which the body names¦A ruling goes into the PR body"
)
for r in "${rules[@]}"; do
  IFS='¦' read -r name clause changed <<<"$r"
  check "$name" yes "$(has "$skill" "$clause")"
  check "$name: the changed clause is refused" no "$(has "$changed" "$clause")"
done
finish
