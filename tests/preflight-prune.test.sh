#!/usr/bin/env bash
# preflight's prune of sibling worktrees: a worktree goes only when its HEAD is
# exactly the head of the merged or closed PR its branch names, so a fresh
# worktree reusing an old PR's branch name, or one that gained commits after its
# PR closed, keeps its work.
#
# Driven over the Host fake inside a throwaway GitHub-origin checkout whose
# sibling container holds one worktree per case; there is no profile, so
# preflight's other reasons are present and beside the point.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
export GIT_ALLOW_PROTOCOL=file
mkdir -p "$repo" "$SHIP_FAKE"
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
g init -q
g remote add origin https://github.com/owner/repo.git
g commit -q --allow-empty -m base

# <name>: a sibling worktree on branch fix/<name>, at the base commit.
worktree() {
  g worktree add -q -b "fix/$1" "$work/repo.worktrees/$1" >/dev/null 2>&1
  printf '%s' "$work/repo.worktrees/$1"
}
# <state> <head_sha>: the PR the fake finds for the one worktree's branch.
pr() {
  rm -f "$SHIP_FAKE"/*
  printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
  printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"
  jq -n --arg s "$1" --arg h "$2" '{number: 7, state: $s, head_sha: $h}' > "$SHIP_FAKE/host_pr_for_branch.1.json"
}
preflight() { ( cd "$repo" && bash "$scripts/preflight.sh" none 2>/dev/null ); }
branch() { g branch --list --format='%(refname:short)' "fix/$1"; }

# A fresh worktree whose branch name an old closed PR used: its HEAD is not that
# PR's head, so it is live work.
wt=$(worktree fresh)
pr closed 0123456789abcdef0123456789abcdef01234567
check "a worktree off another PR's head is not pruned" '[]' "$(preflight | jq -c .pruned)"
check "and survives" true "$([ -d "$wt" ] && echo true)"
g worktree remove --force "$wt"; g branch -D -q fix/fresh

# The merged PR's own leftover: HEAD is its head, so the worktree and its local
# branch go, and pruned[] names it.
wt=$(worktree merged)
pr merged "$(git -C "$wt" rev-parse HEAD)"
check "a worktree at its merged PR's head is pruned" "[\"$wt\"]" "$(preflight | jq -c .pruned)"
check "and removed" false "$([ -d "$wt" ] && echo true || echo false)"
check "with its local branch" '' "$(branch merged)"

# Commits after the PR closed: the head the PR recorded is behind HEAD now.
wt=$(worktree moved)
closed_head=$(git -C "$wt" rev-parse HEAD)
git -C "$wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m more
pr closed "$closed_head"
check "a worktree moved past its closed PR's head is not pruned" '[]' "$(preflight | jq -c .pruned)"
check "and keeps its branch" fix/moved "$(branch moved)"

finish
