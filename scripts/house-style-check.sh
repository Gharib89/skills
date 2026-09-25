#!/usr/bin/env bash
# The em-dash ban from docs/contributing/coding-standards.md, plus no line ending
# in a space or tab and no non-empty file without a final newline, over the files
# this repo authors. A derived repo's stock `trailing-whitespace` and
# `end-of-file-fixer` hooks fail on a copied script that breaks either (issue
# #288). `.claude/skills/` is install output from other repos and is exempt. The
# `house-style` gate in scripts/local-gate.sh runs this, in every lane.
#
# Build the dash from its UTF-8 bytes. A `$'\u2014'` escape expands by locale:
# with LANG and LC_ALL empty (the cloud sandbox) it stays literal escape text and
# matches this script's own source (issue #249). Bytes match under any locale.
#
#   scripts/house-style-check.sh
#
# stdout: the offending lines, and each file missing its final newline; nothing when clean
# exit: 0 clean · 1 a finding · 2 tooling
set -uo pipefail

paths=('skills/*' 'docs/*' 'scripts/*' 'tests/*' '.github/*' '.release/*' CONTEXT.md CLAUDE.md)
found=0

# <heading> <git grep pattern args...>: prints the heading and the hits when any.
# `git grep` over the tracked files: 1 is a clean tree, and anything past 1,
# such as a run outside a checkout, is tooling rather than a clean answer.
grep_rule() {
  local heading=$1 hits
  shift
  hits=$(git grep -n "$@" -- "${paths[@]}")
  case $? in
    0) ;;
    1) return 0 ;;
    *) exit 2 ;;
  esac
  echo "$heading"
  echo "$hits"
  found=1
}

em=$(printf '\342\200\224')
grep_rule "em dashes in repo-authored files (see docs/contributing/coding-standards.md):" -F -e "$em"
grep_rule "trailing whitespace in repo-authored files:" -I -e '[[:blank:]]$'

# A last byte that is a newline is stripped by the substitution, leaving it empty.
missing=$(git ls-files -z -- "${paths[@]}" | while IFS= read -r -d '' f; do
  [ -s "$f" ] && [ -n "$(tail -c 1 "$f")" ] && printf '%s\n' "$f"
done)
if [ -n "$missing" ]; then
  echo "no final newline in repo-authored files:"
  echo "$missing"
  found=1
fi
exit "$found"
