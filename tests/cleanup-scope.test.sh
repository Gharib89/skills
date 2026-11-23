#!/usr/bin/env bash
# `cleanup` removes only the run's own worktree and branch. A free-text run
# (`none`) names the exact branch its PR was opened from, since two free-text
# runs can coexist and an adopted host worktree's branch need not carry the
# slug; a tracked issue with more than one match is refused, nothing removed.
# Driven at the mechanic's entrypoint in a throwaway checkout under a throwaway
# XDG_STATE_HOME; cleanup loads no host adapter, so nothing reaches one.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

c=$PWD/skills/ship/scripts/cleanup.sh
r=$PWD/skills/ship/scripts/run-file.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
export XDG_STATE_HOME=$tmp/state

repo=$tmp/repo
git init -q -b main "$repo"
g() { git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
g commit -q --allow-empty -m one
exists() { [ -e "$1" ] && echo yes || echo no; }

# Two free-text worktrees: cleaning one leaves the other and its untracked file.
g worktree add -q "$tmp/wt-one" -b fix/one-none
g worktree add -q "$tmp/wt-two" -b fix/two-none
echo keep > "$tmp/wt-two/untracked.txt"
out=$(cd "$repo" && bash "$c" none fix/one-none 2>/dev/null); rc=$?
check_rc "free-text cleanup of one run exits ok" 0 "$rc"
check "the JSON names its worktree, branch and both removals" "$tmp/wt-one fix/one-none true true" \
  "$(jq -r '[.worktree, .branch, .worktree_removed, .branch_deleted] | join(" ")' <<<"$out")"
check "its worktree is gone" no "$(exists "$tmp/wt-one")"
check "its branch is gone" "" "$(g branch --list fix/one-none)"
check "the other run's worktree stays" yes "$(exists "$tmp/wt-two")"
check "and its untracked file" keep "$(cat "$tmp/wt-two/untracked.txt" 2>/dev/null)"
check "and its branch" "+ fix/two-none" "$(g branch --list fix/two-none | sed 's/^ *//')"

# An adopted host worktree whose branch differs from the run's slug: the branch
# the PR was opened from is the one torn down.
g worktree add -q "$tmp/t3-odd-1a2b3c4d" -b feat/host-chosen-name
out=$(cd "$repo" && bash "$c" none feat/host-chosen-name 2>/dev/null); rc=$?
check_rc "an adopted worktree on another branch exits ok" 0 "$rc"
check "its worktree and branch are named and removed" "$tmp/t3-odd-1a2b3c4d feat/host-chosen-name true true" \
  "$(jq -r '[.worktree, .branch, .worktree_removed, .branch_deleted] | join(" ")' <<<"$out")"
check "the folder is gone" no "$(exists "$tmp/t3-odd-1a2b3c4d")"
check "the other free-text worktree still stays" yes "$(exists "$tmp/wt-two")"

# No branch for a free-text run is a usage error that removes nothing.
out=$(cd "$repo" && bash "$c" none 2>/dev/null); rc=$?
check_rc "free-text cleanup without a branch exits 2" 2 "$rc"
check "and answers the usage line" true "$(jq -r '.error | startswith("usage: cleanup")' <<<"$out" 2>/dev/null)"
check "and removes nothing" yes "$(exists "$tmp/wt-two")"
check "and keeps the branch" "+ fix/two-none" "$(g branch --list fix/two-none | sed 's/^ *//')"

# A branch no worktree or ref holds: nothing is found, nothing is claimed.
out=$(cd "$repo" && bash "$c" none fix/absent-none 2>/dev/null); rc=$?
check_rc "an absent branch exits ok" 0 "$rc"
check "and reports no worktree and no branch" "null null null" \
  "$(jq -r '[.worktree, .branch, .worktree_removed] | map(tostring) | join(" ")' <<<"$out")"

# A tracked issue with two matching worktrees is refused and names both.
g worktree add -q "$tmp/wt-a" -b feat/a-77
g worktree add -q "$tmp/wt-b" -b fix/b-77
rec=$(dirname "$(cd "$repo" && bash "$r" init 77 | jq -r .scratch)")
out=$(cd "$repo" && bash "$c" 77 2>/dev/null); rc=$?
check_rc "two matching worktrees exit 1" 1 "$rc"
check "branch a is named" yes "$(grep -q feat/a-77 <<<"$(jq -r .error <<<"$out")" && echo yes || echo no)"
check "branch b is named" yes "$(grep -q fix/b-77 <<<"$(jq -r .error <<<"$out")" && echo yes || echo no)"
check "the run's record stays" yes "$([ -f "$rec/ship-77/run.md" ] && echo yes || echo no)"
check "and the refusal reports no record field" null "$(jq -r '.record // "null"' <<<"$out")"
check "worktree a stays" yes "$(exists "$tmp/wt-a")"
check "worktree b stays" yes "$(exists "$tmp/wt-b")"
check "branch a stays" "+ feat/a-77" "$(g branch --list feat/a-77 | sed 's/^ *//')"

# A worktree plus a bare branch both matching is the same refusal.
g worktree add -q "$tmp/wt-c" -b feat/c-78
g branch fix/bare-78
out=$(cd "$repo" && bash "$c" 78 2>/dev/null); rc=$?
check_rc "a worktree and a bare branch exit 1" 1 "$rc"
err=$(jq -r .error <<<"$out")
check "the refusal names the worktree's branch" yes "$(grep -q feat/c-78 <<<"$err" && echo yes || echo no)"
check "and the bare branch" yes "$(grep -q fix/bare-78 <<<"$err" && echo yes || echo no)"
check "the worktree stays" yes "$(exists "$tmp/wt-c")"
check "the bare branch stays" "  fix/bare-78" "$(g branch --list fix/bare-78)"

# A tracked issue takes no branch: the usage line has no such form.
out=$(cd "$repo" && bash "$c" 79 feat/d-79 2>/dev/null); rc=$?
check_rc "a branch given with an issue exits 2" 2 "$rc"
check "and answers the usage line" true "$(jq -r '.error | startswith("usage: cleanup")' <<<"$out")"

# One match behaves as before.
g worktree add -q "$tmp/wt-d" -b feat/d-79
out=$(cd "$repo" && bash "$c" 79 2>/dev/null); rc=$?
check_rc "a single match exits ok" 0 "$rc"
check "and is removed" "$tmp/wt-d feat/d-79 true true" \
  "$(jq -r '[.worktree, .branch, .worktree_removed, .branch_deleted] | join(" ")' <<<"$out")"

finish
