#!/usr/bin/env bash
# The em-dash ban from docs/contributing/coding-standards.md, over the files this
# repo authors. `.claude/skills/` is install output from other repos and is
# exempt. The `house-style` gate in scripts/local-gate.sh runs this, in every lane.
#
# Build the dash from its UTF-8 bytes. A `$'\u2014'` escape expands by locale:
# with LANG and LC_ALL empty (the cloud sandbox) it stays literal escape text and
# matches this script's own source (issue #249). Bytes match under any locale.
#
#   scripts/house-style-check.sh
#
# stdout: the offending lines, nothing when clean
# exit: 0 clean · 1 an em dash · 2 tooling
set -uo pipefail

em=$(printf '\342\200\224')
# `git grep` over the tracked files: 1 is a clean tree, and anything past 1,
# such as a run outside a checkout, is tooling rather than a clean answer.
hits=$(git grep -n -F -e "$em" -- 'skills/*' 'docs/*' 'scripts/*' 'tests/*' '.github/*' '.release/*' CONTEXT.md CLAUDE.md)
case $? in
  0) ;;
  1) exit 0 ;;
  *) exit 2 ;;
esac
echo "em dashes in repo-authored files (see docs/contributing/coding-standards.md):"
echo "$hits"
exit 1
