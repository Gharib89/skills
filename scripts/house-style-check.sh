#!/usr/bin/env bash
# The em-dash ban from docs/contributing/coding-standards.md, over the files this
# repo authors. `.claude/skills/` is install output from other repos and is
# exempt. The `house-style` gate in scripts/local-gate.sh runs this, in every lane.
#
# The dash is built from its UTF-8 bytes rather than a `$'\u'` escape, whose expansion
# depends on the locale: with LANG and LC_ALL empty, as in the cloud sandbox, it
# stays escape text, and grep then matched this check's own source (issue #249).
# Bytes match bytes under any locale.
#
#   scripts/house-style-check.sh
#
# stdout: the offending lines, nothing when clean
# exit: 0 clean · 1 an em dash
set -uo pipefail

em=$(printf '\342\200\224')
hits=$(git ls-files -z 'skills/*' 'docs/*' 'scripts/*' 'tests/*' '.github/*' '.release/*' CONTEXT.md CLAUDE.md \
  | xargs -0 grep -n "$em" 2>/dev/null) || exit 0
echo "em dashes in repo-authored files (see docs/contributing/coding-standards.md):"
echo "$hits"
exit 1
