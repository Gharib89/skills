#!/usr/bin/env bash
# update-skills names the preflight reasons a refresh expects from its own run.
# Preflight reads `existing branch` from the remote, and `isolate` creates the
# branch locally; no preflight runs after step 8 pushes it, so the run's own
# reasons are `worktree exists` alone. A reading of prose: no line of the skill
# names `existing branch`, and its Verification item expects the `worktree
# exists` reason, so a negated item (not the expected reason) fails. Reads files
# only; no call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

# Prints 1 when the step-8 `## Verification` bullet, its continuation lines
# joined, names the expected `worktree exists` reason with no negation in it.
expects_worktree_reason() {
  awk '/^- `## Verification`:/ { f = 1 } f && /^- / && !/Verification/ { f = 0 } f' "$1" | tr '\n' ' ' \
    | grep -F 'the expected `worktree exists` reason' | grep -cviwE 'not|no|never|without|nor'
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf -- '- `## Verification`: the reasons,\n  the expected `worktree exists` reason, and the verdict.\n- next\n' >"$tmp/kept.md"
printf -- '- `## Verification`: the reasons,\n  not the expected `worktree exists` reason, and the verdict.\n- next\n' >"$tmp/negated.md"
printf -- '- `## Verification`: the reasons and the verdict.\n- the expected `worktree exists` reason\n' >"$tmp/elsewhere.md"

check "fixture: an item expecting the reason passes" 1 "$(expects_worktree_reason "$tmp/kept.md")"
check "fixture: a negated item is caught" 0 "$(expects_worktree_reason "$tmp/negated.md")"
check "fixture: the phrase outside the item is caught" 0 "$(expects_worktree_reason "$tmp/elsewhere.md")"

skill=skills/update-skills/SKILL.md
check "update-skills expects no \`existing branch\`" "" "$(grep -nF '`existing branch`' "$skill")"
check "update-skills' Verification item names the expected worktree exists reason" 1 \
  "$(expects_worktree_reason "$skill")"

finish
