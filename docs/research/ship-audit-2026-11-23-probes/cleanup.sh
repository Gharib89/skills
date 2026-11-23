#!/usr/bin/env bash
set -eu -o pipefail
src=$PWD/skills/ship/scripts
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
repo=$work/repo
git init -q -b main "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
g commit -q --allow-empty -m base
g worktree add -qb fix/beta-none "$work/1-beta"
g worktree add -qb fix/alpha-none "$work/2-alpha"
echo 'Unrelated beta WIP' > "$work/1-beta/working-draft.txt"
echo 'Calling cleanup none from Alpha worktree'
(cd "$work/2-alpha" && bash "$src/cleanup.sh" none)
for wt in "$work/1-beta" "$work/2-alpha"; do
  if [ -d "$wt" ]; then echo "$(basename "$wt"): kept"; else echo "$(basename "$wt"): removed"; fi
done
