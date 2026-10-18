#!/usr/bin/env bash
# The turn rung's shell row (scripts/check.sh TURN_ROWS): run the tests an edit
# to shell code can break. An edited tests/*.test.sh selects itself; any other
# .sh selects every tests/*.test.sh whose text names its basename, and ship's
# _lib.sh and each piece in its lib/ directory select the tests naming
# `_lib.sh`, since a piece is sourced, not named. A file no test names selects
# nothing and is no failure. The selection runs through tests/run.sh, not the
# files directly, because the runner is what puts the host stub in front of PATH.
#
#   scripts/shell-turn-tests.sh [--list] <file>...
#
# stdout: tests/run.sh's report; with --list, the selected files, one per line
# exit: tests/run.sh's, 0 when nothing is selected
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

list=''
[ "${1:-}" = --list ] && { list=1; shift; }

selected=''
for f; do
  case $f in
    tests/*.test.sh) selected="$selected$f"$'\n'; continue ;;
    skills/ship/scripts/lib/*.sh) name=_lib.sh ;;
    *) name=${f##*/} ;;
  esac
  selected="$selected$(grep -lF -- "$name" tests/*.test.sh)"$'\n'
done
selected=$(printf '%s' "$selected" | sort -u | sed '/^$/d')

[ -n "$selected" ] || exit 0
if [ -n "$list" ]; then printf '%s\n' "$selected"; exit 0; fi
IFS=$'\n' read -r -d '' -a files <<< "$selected"
exec bash tests/run.sh "${files[@]}"
