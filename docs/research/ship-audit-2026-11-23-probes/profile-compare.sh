#!/usr/bin/env bash
# Two ways a working-tree-only `git diff <base> -- docs/agents/ship.md` misses a
# profile change the PR carries or the gate reads. Pure git.
#   1. The branch commits a profile change and the checkout reverts it locally:
#      the working-tree diff is empty while the committed diff is not.
#   2. The base has no profile and the checkout holds an untracked one: the
#      working-tree diff is empty while the file is there to be read.
set -uo pipefail
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
p=docs/agents/ship.md
lines() { wc -l | tr -d ' '; }

repo=$work/committed
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
git init -q -b main "$repo"; mkdir -p "$repo/docs/agents"
printf 'Merge: Default.\n' > "$repo/$p"
g add "$p"; g commit -q -m base
g checkout -q -b fix/x
printf 'Merge: on-clean-gate\n' > "$repo/$p"
g commit -qam 'change the profile'
printf 'Merge: Default.\n' > "$repo/$p"
echo 'Case 1: committed profile change, reverted in the working tree only'
echo "  git diff main -- $p (working tree): $(g diff main -- "$p" | lines) lines"
echo "  git diff main HEAD -- $p (committed): $(g diff main HEAD -- "$p" | lines) lines"

repo=$work/untracked
git init -q -b main "$repo"
g commit -q --allow-empty -m base
g checkout -q -b fix/y
mkdir -p "$repo/docs/agents"; printf 'Merge: on-clean-gate\n' > "$repo/$p"
echo 'Case 2: no profile on the base, an untracked first profile in the checkout'
echo "  git diff main -- $p (working tree): $(g diff main -- "$p" | lines) lines"
echo "  profile file present in the checkout: $([ -f "$repo/$p" ] && echo yes || echo no)"
echo "  git status --porcelain -- $p: $(g status --porcelain -- "$p")"
