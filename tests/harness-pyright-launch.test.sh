#!/usr/bin/env bash
# skills/setup-harness/templates/pyright-launch.sh: the vendored pyright
# plugin's launcher. The subject is the PATH pyright starts with, since pyright
# with no pythonPath asks the first `python` on it. A fake `npx` in front of
# PATH reports the PATH and arguments it got, and the launch runs from the
# served root, as Claude Code runs it: a main checkout, or a worktree of it
# under .claude/worktrees/.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
script=$PWD/skills/setup-harness/templates/pyright-launch.sh
main=$fixture/main wt=$fixture/main/.claude/worktrees/w

mkdir -p "$fixture/bin" "$main"
printf '#!/bin/sh\necho "$PATH"\necho "$*"\n' > "$fixture/bin/npx"
chmod +x "$fixture/bin/npx"
git -C "$main" init -q && git -C "$main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$main" worktree add -q "$wt"
venv() { mkdir -p "$1/.venv/bin" && : > "$1/.venv/bin/python" && chmod +x "$1/.venv/bin/python"; }

path=$fixture/bin:$PATH
launch() { out=$(cd "$1" && PATH=$path bash "$script" "${@:2}" 2>/dev/null); rc=$?; }

launch "$wt" 1.1.414 .
check_rc "a launch with no venv anywhere runs pyright" 0 "$rc"
check "with no venv anywhere PATH is unchanged" "$path" "$(sed -n 1p <<< "$out")"
check "the pinned pyright-langserver gets --stdio" "--yes --package=pyright@1.1.414 pyright-langserver --stdio" "$(sed -n 2p <<< "$out")"

venv "$main"
launch "$wt" 1.1.414 .
check "a worktree with no venv takes the main checkout's" "$main/.venv/bin:$path" "$(sed -n 1p <<< "$out")"
launch "$main" 1.1.414 .
check "the main checkout takes its own venv" "$main/.venv/bin:$path" "$(sed -n 1p <<< "$out")"

venv "$wt"
launch "$wt" 1.1.414 .
check "a worktree with its own venv takes it first" "$wt/.venv/bin:$path" "$(sed -n 1p <<< "$out")"

venv "$main/api"
launch "$wt" 1.1.414 api
check "a stack root below the repo root is where the venv is looked for" "$main/api/.venv/bin:$path" "$(sed -n 1p <<< "$out")"

launch "$wt" 1.1.414
check_rc "a launch with no stack root is a usage error" 2 "$rc"

finish
