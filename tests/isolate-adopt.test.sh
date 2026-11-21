#!/usr/bin/env bash
# `isolate <n> ...` run from a linked worktree a host launched the session in,
# on a `<type>/<slug>-<n>` branch, adopts it rather than refusing `existing branch`:
# clean and with no commits beyond origin/HEAD, it is fast-forwarded there and
# printed with `reused: true`. A dirty one, one carrying its own commits and the
# main checkout are refused; a branch not of that shape is not adopted.
# `cleanup` then removes the host's folder and branch. Driven over a clone
# of a local bare origin; neither mechanic loads a host adapter.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=$PWD/skills/ship/scripts/isolate.sh
c=$PWD/skills/ship/scripts/cleanup.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P)
export XDG_STATE_HOME=$tmp/state
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

seed=$tmp/seed
{
  git init -q -b main "$seed"
  g -C "$seed" commit -q --allow-empty -m one
  g -C "$seed" commit -q --allow-empty -m two
  git clone -q --bare "$seed" "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/repo"
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
repo=$tmp/repo
tip=$(git -C "$repo" rev-parse origin/main)
# launch <dir> <branch>: a host-made worktree outside .claude/worktrees/, one
# commit behind origin/HEAD, as T3 leaves it when the default moved since.
launch() { git -C "$repo" worktree add -q "$1" -b "$2" "$tip~1" >/dev/null 2>&1; }

host=$tmp/host/t3-a
launch "$host" feat/launch-name-7
out=$(cd "$host" && bash "$m" 7 feat launch-name 2>/dev/null); rc=$?
check_rc "a clean launched worktree on the run's own branch is adopted" 0 "$rc"
check "it is printed as reused, on its own branch, based on origin/HEAD" \
  "$host feat/launch-name-7 origin/main false true" \
  "$(jq -r '"\(.worktree) \(.branch) \(.base) \(.in_place) \(.reused)"' <<<"$out")"
check "it is fast-forwarded to origin/HEAD" "$tip" "$(git -C "$host" rev-parse HEAD)"
check "no worktree is made under .claude/worktrees/" "" "$(ls "$repo/.claude/worktrees" 2>/dev/null)"

# The run's slug need not be the launcher's: any `<type>/<slug>-<n>` branch is adopted.
out=$(cd "$host" && bash "$m" 7 feat x --in-place 2>/dev/null); rc=$?
check_rc "--in-place adopts it under another slug too" 0 "$rc"
check "with in_place true" "$host true true" "$(jq -r '"\(.worktree) \(.in_place) \(.reused)"' <<<"$out")"

echo s > "$repo/secret.env"
out=$(cd "$host" && bash "$m" 7 feat x --carry secret.env 2>/dev/null); rc=$?
check_rc "--carry into an adopted worktree exits ok" 0 "$rc"
check "the file is carried into it" "secret.env s" "$(jq -r '.carried | join(",")' <<<"$out") $(cat "$host/secret.env" 2>/dev/null)"
rm -f "$repo/secret.env" "$host/secret.env"

touch "$host/dirty"
out=$(cd "$host" && bash "$m" 7 feat x 2>/dev/null); rc=$?
check_rc "a dirty launched worktree is refused" 1 "$rc"
check "the refusal names it" "launched worktree dirty: $host" "$(jq -r .error <<<"$out")"
rm "$host/dirty"

g -C "$host" commit -q --allow-empty -m own
out=$(cd "$host" && bash "$m" 7 feat x 2>/dev/null); rc=$?
check_rc "a launched branch with its own commits is refused" 1 "$rc"
check "the refusal names the branch" "launched branch feat/launch-name-7 has commits beyond origin/main" \
  "$(jq -r .error <<<"$out")"

# `-80` is a near miss for issue 8: the suffix must be exactly `-<n>`.
other=$tmp/host/t3-b
launch "$other" feat/other-80
out=$(cd "$other" && bash "$m" 8 feat x 2>/dev/null); rc=$?
check_rc "a launched branch not ending -<n> isolates as before" 0 "$rc"
check "it is not adopted: a fresh worktree is made" "$repo/.claude/worktrees/x-8 false" \
  "$(jq -r '"\(.worktree) \(.reused)"' <<<"$out")"

# A slashless `-<n>` branch is not isolate's shape, so cleanup would leave it:
# it is not adopted either, and the run gets a worktree cleanup removes.
slashless=$tmp/host/t3-c
launch "$slashless" launch-name-6
out=$(cd "$slashless" && bash "$m" 6 feat x 2>/dev/null); rc=$?
check_rc "a launched slashless -<n> branch isolates as before" 0 "$rc"
check "it is not adopted: a fresh worktree is made" "$repo/.claude/worktrees/x-6 false" \
  "$(jq -r '"\(.worktree) \(.reused)"' <<<"$out")"

out=$(cd "$repo/.claude/worktrees/x-8" && bash "$m" 8 feat x 2>/dev/null); rc=$?
check_rc "ship's own worktree under .claude/worktrees/ is not adopted" 1 "$rc"
check "it is refused as before" "existing branch: feat/x-8" "$(jq -r .error <<<"$out")"

g -C "$repo" switch -q -c feat/x-9 "$tip" >/dev/null 2>&1
out=$(cd "$repo" && bash "$m" 9 feat x --in-place 2>/dev/null); rc=$?
check_rc "the main checkout on a -<n> branch is not adopted" 1 "$rc"
check "it is refused as before" "existing branch: feat/x-9" "$(jq -r .error <<<"$out")"
out=$(cd "$repo" && bash "$m" 9 feat x 2>/dev/null); rc=$?
check_rc "nor attended" 1 "$rc"
check "the attended refusal is the same" "existing branch: feat/x-9" "$(jq -r .error <<<"$out")"
# `cleanup` removes the adopted worktree and its branch, finding it by branch
# since the host named the folder.
g -C "$host" reset -q --hard "$tip"
out=$(cd "$host" && bash "$c" 7 2>/dev/null); rc=$?
check_rc "cleanup after an adopted run exits ok" 0 "$rc"
check "it removes the host's worktree and its branch" "$host feat/launch-name-7 true true" \
  "$(jq -r '"\(.worktree) \(.branch) \(.worktree_removed) \(.branch_deleted)"' <<<"$out")"
check "the host's folder is gone" no "$([ -e "$host" ] && echo yes || echo no)"

finish
