#!/usr/bin/env bash
# update-skills step 8 (#1035): a refresh that edits a file a run executes
# draws a behavioural `diff` fence, and the closing cleanup line removes the
# refresh's worktree, local branch and remote branch by the names step 1 noted.
# `cleanup.sh none` from the main checkout ran the merged ship copy, which looks
# for worktrees in its own container (moved by #585), and deletes no remote
# branch, so it removed nothing. A reading of prose; no call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

# Prints the count of stdin's sentences, lines joined, that name <phrase> with no
# negation in them, so a reworded "with no `diff` fence" reads 0.
affirms() { tr '\n' ' ' | sed 's/\. /.\n/g' | grep -F "$1" | grep -cviwE 'no|not|never|without|nor'; }

check "fixture: a sentence drawing the fence passes" 1 \
  "$(printf 'The outline opens instead\nwith one `diff` fence. Then:\n' | affirms 'with one `diff` fence')"
check "fixture: a negated sentence is caught" 0 \
  "$(printf 'The outline opens instead\nwith one `diff` fence never. Then:\n' | affirms 'with one `diff` fence')"

skill=skills/update-skills/SKILL.md
step() { awk -v h="### $1." 'index($0, h) == 1 { f = 1; next } f && /^#{2,3} / { exit } f' "$skill"; }
step1=$(step 1)
step8=$(step 8)
closing=$(printf '%s\n' "$step8" | awk '/^Open it with/ { f = 1 } f')
line=$(printf '%s\n' "$closing" | awk '/^```sh$/ { f = 1; next } /^```$/ { f = 0 } f')
outline=$(printf '%s\n' "$step8" | awk '/^- `## Change outline`:/ { f = 1; print; next } f && /^- / { exit } f')

check "step 1 notes isolate's worktree and branch" 1 "$(printf '%s\n' "$step1" | affirms '`worktree` and `branch`')"
check "the closing hands the owner no cleanup.sh none" 0 "$(printf '%s\n' "$closing" | grep -cF 'cleanup.sh none')"
for c in 'git worktree remove --force <worktree>' 'git branch -D <branch>' 'git push origin --delete <branch>' \
  'git fetch --prune origin'; do
  check "the handed line runs: $c" 1 "$(printf '%s\n' "$line" | grep -cF "$c")"
done
check "the outline draws a diff fence for a file a run executes" 1 \
  "$(printf '%s\n' "$outline" | affirms 'with one `diff` fence')"
check "the mechanical Shape stays for the skill copies" 1 \
  "$(printf '%s\n' "$outline" | grep -cF 'Shape: mechanical for the skill copies (skills refresh).')"

finish
