#!/usr/bin/env bash
# `cleanup` also removes the run's record: <git common dir>/ship/ship-<issue>
# and scratch-<issue>, before the worktree goes. Driven over a fixture repo with
# a worktree in the `<repo>.worktrees/<type>-<slug>-<issue>` layout the mechanic
# globs; cleanup loads no host adapter, so nothing reaches one.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

c=$PWD/skills/ship/scripts/cleanup.sh
r=$PWD/skills/ship/scripts/run-file.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

repo=$tmp/repo
git init -q -b main "$repo"
g() { git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
g commit -q --allow-empty -m one
root=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/ship

mk() { # mk <issue>: a worktree, a branch and a record for the issue
  g worktree add -q "$tmp/repo.worktrees/feat-$1" -b "feat/x-$1"
  ( cd "$repo" && bash "$r" init "$1" >/dev/null )
  echo "scratch" > "$root/scratch-$1/note"
}

mk 7
out=$(cd "$repo" && bash "$c" 7 2>/dev/null); rc=$?
check_rc "cleanup exits ok" 0 "$rc"
check "the JSON says the record was removed" true "$(jq -r .record_removed <<<"$out")"
check "the run file is gone" no "$([ -e "$root/ship-7" ] && echo yes || echo no)"
check "the scratch directory is gone" no "$([ -e "$root/scratch-7" ] && echo yes || echo no)"
check "the worktree is still removed" no "$([ -e "$tmp/repo.worktrees/feat-7" ] && echo yes || echo no)"
check "the worktree fields are unchanged" "$tmp/repo.worktrees/feat-7 feat/x-7 true true" \
  "$(jq -r '[.worktree, .branch, .worktree_removed, .branch_deleted] | join(" ")' <<<"$out")"

# Another issue's record is not this issue's to remove.
mk 8; mk 9
( cd "$repo" && bash "$c" 8 >/dev/null 2>&1 )
check "another issue's record stays" yes "$([ -f "$root/ship-9/run.md" ] && [ -d "$root/scratch-9" ] && echo yes || echo no)"

# Cleanup run from inside the worktree whose record it removes: the record
# lives under the common dir, so the worktree's removal is not in its way.
out=$(cd "$tmp/repo.worktrees/feat-9" && bash "$c" 9 2>/dev/null)
check "cleanup from inside the worktree removes the record" true "$(jq -r .record_removed <<<"$out")"

# No record to remove is false, and not a failure.
out=$(cd "$repo" && bash "$c" 55 2>/dev/null); rc=$?
check "an issue with no record answers false" false "$(jq -r .record_removed <<<"$out")"
check_rc "and exits ok" 0 "$rc"

# `none` is the task-spec run's suffix, not an issue: its record is left to the
# run that names it.
( cd "$repo" && bash "$r" init none >/dev/null )
out=$(cd "$repo" && bash "$c" none 2>/dev/null)
check "none answers false" false "$(jq -r .record_removed <<<"$out")"
check "none leaves its record" yes "$([ -f "$root/ship-none/run.md" ] && echo yes || echo no)"

finish
