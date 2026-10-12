#!/usr/bin/env bash
# `isolate <n> <type> <slug> --rework` puts a Rework run on the PR's existing
# branch rather than a fresh one off the default: it reuses the worktree an
# ended attended run left when that one is clean and at origin's tip of the
# branch, and otherwise checks the branch out into a new worktree. Its `base` is
# that tip, which the rework's own diff counts from. Driven end to end over a
# clone of a local bare origin; isolate loads no host adapter.
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
  g -C "$seed" branch feat/x-7
  g -C "$seed" checkout -q feat/x-7
  g -C "$seed" commit -q --allow-empty -m pr
  g -C "$seed" checkout -q main
  git clone -q --bare "$seed" "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/repo"
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
repo=$tmp/repo
tip=$(git -C "$tmp/origin.git" rev-parse feat/x-7)
wt=$repo/.claude/worktrees/x-7

out=$(cd "$repo" && bash "$m" 7 feat x --rework 2>/dev/null); rc=$?
check_rc "isolate --rework exits ok with no worktree" 0 "$rc"
check "the worktree is new, on the PR branch at origin's tip" "$wt feat/x-7 $tip false" \
  "$(jq -r '"\(.worktree) \(.branch) \(.base) \(.reused)"' <<<"$out")"
check "the worktree's HEAD is the tip" "$tip" "$(git -C "$wt" rev-parse HEAD)"

out=$(cd "$repo" && bash "$m" 7 feat x --rework 2>/dev/null); rc=$?
check_rc "a clean worktree at the tip is reused" 0 "$rc"
check "reused names the same worktree" "$wt true" "$(jq -r '"\(.worktree) \(.reused)"' <<<"$out")"

touch "$wt/dirty"
out=$(cd "$repo" && bash "$m" 7 feat x --rework 2>/dev/null); rc=$?
check_rc "a dirty worktree is refused" 1 "$rc"
check "the refusal names it" "worktree exists: $wt" "$(jq -r .error <<<"$out")"

out=$(cd "$repo" && bash "$m" 8 feat y --rework 2>/dev/null); rc=$?
check_rc "a branch origin lacks is refused" 1 "$rc"
check "the refusal names the branch" "no PR branch on origin: feat/y-8" "$(jq -r .error <<<"$out")"

check_rc "--rework has no in-place form" 2 \
  "$(cd "$repo" && bash "$m" 7 feat x --rework --in-place >/dev/null 2>&1; echo $?)"

finish
