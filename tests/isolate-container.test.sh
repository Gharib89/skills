#!/usr/bin/env bash
# `isolate` lands an attended run's worktree under the main checkout's
# `.claude/worktrees/`, the one place `EnterWorktree` enters without a permission
# prompt, and lists that folder in the repo's shared exclude file once, so the
# main checkout's `git status` stays clean. `--in-place` does neither. Driven end
# to end over a clone of a local bare origin; isolate loads no host adapter.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=$PWD/skills/ship/scripts/isolate.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

seed=$tmp/seed
git init -q -b main "$seed"
git -C "$seed" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m one
git clone -q --bare "$seed" "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/repo"
git clone -q "$tmp/origin.git" "$tmp/clone"
repo=$tmp/repo
exclude=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/info/exclude

out=$(cd "$repo" && bash "$m" 7 feat x 2>/dev/null); rc=$?
check_rc "isolate exits ok" 0 "$rc"
check "the worktree sits under .claude/worktrees" "$repo/.claude/worktrees/x-7" "$(jq -r .worktree <<<"$out")"
check "the worktree exists" yes "$([ -d "$repo/.claude/worktrees/x-7" ] && echo yes || echo no)"

# A second run must not add the line again.
( cd "$repo" && bash "$m" 8 feat y >/dev/null 2>&1 )
check "the exclude file lists the container once" 1 "$(grep -cxF '.claude/worktrees/' "$exclude")"
check "the main checkout's status stays clean" "" "$(git -C "$repo" status --porcelain)"

# Run from inside a worktree: the container is still the main checkout's.
out=$(cd "$repo/.claude/worktrees/x-7" && bash "$m" 9 feat z 2>/dev/null)
check "a run from a worktree uses the main checkout's container" "$repo/.claude/worktrees/z-9" "$(jq -r .worktree <<<"$out")"

# The matcher takes whole lines only, and a last line with no newline keeps
# its own line.
git clone -q "$tmp/origin.git" "$tmp/edge"
edge_exclude=$(git -C "$tmp/edge" rev-parse --path-format=absolute --git-common-dir)/info/exclude
printf '.claude/worktrees/keep\n*.log' >"$edge_exclude"
( cd "$tmp/edge" && bash "$m" 7 feat x >/dev/null 2>&1 )
check "a longer path is not the entry, and the unterminated line stays whole" \
  ".claude/worktrees/keep|*.log|.claude/worktrees/" "$(paste -sd'|' "$edge_exclude")"

clone=$tmp/clone
out=$(cd "$clone" && bash "$m" 7 feat x --in-place 2>/dev/null); rc=$?
check_rc "isolate --in-place exits ok" 0 "$rc"
check "--in-place creates no container" no "$([ -e "$clone/.claude/worktrees" ] && echo yes || echo no)"
check "--in-place writes no exclude line" 0 \
  "$(grep -cxF '.claude/worktrees/' "$(git -C "$clone" rev-parse --path-format=absolute --git-common-dir)/info/exclude")"

finish
