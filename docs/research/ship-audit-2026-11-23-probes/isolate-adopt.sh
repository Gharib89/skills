#!/usr/bin/env bash
# A free-text run's `isolate none fix user-slug`, called from a worktree a host
# launched on a branch that happens to end in `-none`: isolate adopts that
# worktree and returns its branch, not the branch the run's own slug names.
# Driven over a clone of a local bare origin. Run from the repo root.
set -uo pipefail
m=$PWD/skills/ship-run/scripts/isolate.sh
work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
work=$(cd "$work" && pwd -P)
export XDG_STATE_HOME=$work/state
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
{
  git init -q -b main "$work/seed"
  g -C "$work/seed" commit -q --allow-empty -m one
  git clone -q --bare "$work/seed" "$work/origin.git"
  git clone -q "$work/origin.git" "$work/repo"
  git -C "$work/repo" worktree add -q "$work/host/launched" -b fix/host-slug-none origin/main
} >/dev/null 2>&1 || { echo 'fixture setup failed' >&2; exit 2; }

echo 'isolate none fix user-slug, from the host-launched worktree:'
(cd "$work/host/launched" && bash "$m" none fix user-slug 2>/dev/null \
  | jq -c --arg w "$work/" '{worktree: (.worktree | ltrimstr($w)), branch, reused}'; echo "rc=${PIPESTATUS[0]}")
echo "branch the run's own slug names: fix/user-slug-none"
