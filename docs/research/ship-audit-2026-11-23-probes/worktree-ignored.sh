#!/usr/bin/env bash
# Plain `git worktree remove` (no --force) on a worktree whose only extra file
# is ignored: it exits 0 and the ignored draft goes with the directory. An
# untracked, not ignored file makes the same command refuse. Pure git.
set -uo pipefail
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
git init -q -b main "$repo"
echo '*.draft' > "$repo/.gitignore"
g add .gitignore; g commit -q -m base
git --version

g worktree add -q -b fix/ignored "$work/ignored"
echo notes > "$work/ignored/plan.draft"
echo "status --porcelain in the worktree holding an ignored draft: '$(git -C "$work/ignored" status --porcelain)'"
g worktree remove "$work/ignored"; echo "git worktree remove rc=$?"
if [ -e "$work/ignored/plan.draft" ]; then echo 'ignored draft survived'; else echo 'ignored draft deleted'; fi

g worktree add -q -b fix/untracked "$work/untracked"
echo notes > "$work/untracked/plan.txt"
g worktree remove "$work/untracked" 2>&1; echo "git worktree remove rc=$? on an untracked, not ignored file"
if [ -e "$work/untracked/plan.txt" ]; then echo 'untracked file survived'; else echo 'untracked file deleted'; fi
