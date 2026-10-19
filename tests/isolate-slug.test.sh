#!/usr/bin/env bash
# `isolate <n> <type> <slug>` names the branch `<type>/<slug>-<n>` and the
# worktree `<slug>-<n>`: a slug already ending in `-<n>` gets the number once,
# not twice (ship-862's `feat/check-turn-shell-tests-862-862`). `--rework`
# resolves the PR's own branch, so an existing doubled one is still reached.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=$PWD/skills/ship/scripts/isolate.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

seed=$tmp/seed
{
  git init -q -b main "$seed"
  g -C "$seed" commit -q --allow-empty -m one
  g -C "$seed" branch feat/x-9-9
  git clone -q --bare "$seed" "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/repo"
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
repo=$tmp/repo

out=$(cd "$repo" && bash "$m" 7 feat x-7 2>/dev/null); rc=$?
check_rc "a slug ending in the issue number isolates" 0 "$rc"
check "the number appears once in branch and worktree" \
  "$repo/.claude/worktrees/x-7 feat/x-7" "$(jq -r '"\(.worktree) \(.branch)"' <<<"$out")"

out=$(cd "$repo" && bash "$m" 8 feat x-7 2>/dev/null); rc=$?
check_rc "a slug ending in another number isolates" 0 "$rc"
check "it is unchanged" \
  "$repo/.claude/worktrees/x-7-8 feat/x-7-8" "$(jq -r '"\(.worktree) \(.branch)"' <<<"$out")"

out=$(cd "$repo" && bash "$m" 6 feat y 2>/dev/null)
check "a slug without the number is unchanged" \
  "$repo/.claude/worktrees/y-6 feat/y-6" "$(jq -r '"\(.worktree) \(.branch)"' <<<"$out")"

out=$(cd "$repo" && bash "$m" 9 feat x-9 --rework 2>/dev/null); rc=$?
check_rc "--rework reaches an existing doubled branch" 0 "$rc"
check "it keeps the PR's own branch name" \
  "$repo/.claude/worktrees/x-9-9 feat/x-9-9" "$(jq -r '"\(.worktree) \(.branch)"' <<<"$out")"

finish
