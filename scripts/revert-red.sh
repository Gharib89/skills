#!/usr/bin/env bash
# revert-red: prove a test fails for the reason it exists, by running it on a
# tree with the fix taken out.
#
# A test written to prove a fix proves nothing until it has been red without the
# fix, and a vacuous assertion reads exactly like a sound one in a diff (the
# coding standards' reverted-fix rule). This does the revert in a temp worktree at
# HEAD, so the working tree is never touched: each <path> is restored from the
# merge base with origin/HEAD, or deleted where the fix added it, and the test
# runs there. It reads committed state, so commit the test and the fix first.
#
#   scripts/revert-red.sh <test> <path>...
#
# <test> and each <path> are files relative to the repo root.
# stdout: one line saying whether the test went red
# stderr: the test's last 40 lines when it went red, the evidence it failed
# exit: 0 the test went red on the reverted tree · 1 it stayed green, so it does
#       not prove the fix · 2 tooling or a bad call, which is not a verdict
set -uo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: revert-red <test> <path>..." >&2
  exit 2
fi
test_path=$1
shift

cd "$(git rev-parse --show-toplevel)" || exit 2
root=$PWD
base=$(git merge-base HEAD origin/HEAD 2>/dev/null) || {
  echo "revert-red: no merge base between HEAD and origin/HEAD" >&2
  exit 2
}

# A test bash cannot open exits non-zero and would read as red; a mistyped path
# reverts nothing, so the test stays green and would read as vacuous.
git cat-file -e "HEAD:$test_path" 2>/dev/null || {
  echo "revert-red: $test_path is not committed at HEAD" >&2
  exit 2
}
for p in "$@"; do
  # The test among its own paths would be deleted or reverted, and bash failing to
  # open it reads as red.
  [ "$p" != "$test_path" ] || { echo "revert-red: $p is the test, not a path to revert" >&2; exit 2; }
  git cat-file -e "$base:$p" 2>/dev/null || git cat-file -e "HEAD:$p" 2>/dev/null || {
    echo "revert-red: $p exists at neither the merge base nor HEAD" >&2
    exit 2
  }
done

tmp=$(mktemp -d) || exit 2
wt=$tmp/tree
log=$tmp/test.log
trap 'git -C "$root" worktree remove --force "$wt" 2>/dev/null; rm -rf "$tmp"' EXIT
git worktree add -q --detach "$wt" HEAD || exit 2

for p in "$@"; do
  if git cat-file -e "$base:$p" 2>/dev/null; then
    git -C "$wt" checkout -q "$base" -- "$p" || exit 2
  else
    rm -f "$wt/$p"
  fi
done

(cd "$wt" && bash "$test_path") >"$log" 2>&1
rc=$?

list=$(printf '%s, ' "$@")
list=${list%, }
if [ "$rc" -eq 0 ]; then
  echo "revert-red: $test_path stays green with $list reverted, so it does not prove the fix."
  exit 1
fi
tail -n 40 "$log" >&2
echo "revert-red: $test_path goes red with $list reverted."
