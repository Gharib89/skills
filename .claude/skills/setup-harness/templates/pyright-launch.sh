#!/usr/bin/env bash
# .claude/skills/harness-pyright-lsp/pyright-launch.sh: the vendored pyright
# plugin's launcher, written by setup-harness. Its `.lsp.json` launches it with
# the pinned version and the stack root (`.` at the repo root); re-run
# setup-harness to move them.
#
#   pyright-launch.sh <version> <stack root>
#
# pyright given no interpreter setting asks the first `python` on PATH, so the
# launch puts a venv's bin first: the served root's `<stack root>/.venv`, else
# the main checkout's, which serves a worktree that has none (Claude Code
# starts the server in the served root, a ship worktree included). With
# neither, PATH is left as it is. An interpreter path in `settings` cannot do
# this: pyright resolves it against the served root alone.
#
# exit: 2 usage
set -uo pipefail
[ $# -eq 2 ] || { echo "usage: pyright-launch.sh <version> <stack root>" >&2; exit 2; }
version=$1 sub=/$2
[ "$2" = . ] && sub=
venv=$PWD$sub/.venv/bin
if [ ! -x "$venv/python" ] && common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  venv=${common%/*}$sub/.venv/bin
fi
[ -x "$venv/python" ] && PATH=$venv:$PATH
exec npx --yes --package="pyright@$version" pyright-langserver --stdio
