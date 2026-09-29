#!/usr/bin/env bash
# The GitHub Actions a setup-skills reviewer template installs in a consumer:
# every `uses:` pins a 40-hex commit SHA with a `# vX.Y.Z` comment, because
# setup-harness wires zizmor whose `unpinned-uses` fails on a tag ref; every
# `actions/checkout` sets `persist-credentials: false`, because no template
# step pushes; and this repo's own claude-review.yml, a copy of the template,
# pins the same refs. Reads files only; no call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

tpl=skills/setup-skills/reviewers/github-claude-review.md
own=.github/workflows/claude-review.yml

uses() { sed -n 's/^ *\(- *\)\{0,1\}uses: *//p' "$1"; }

# A file that vanished or lost its steps would pass every case below on empty
# output, so each must yield at least one ref before it is judged.
check "the template has uses: lines to judge" "yes" "$(uses "$tpl" | grep -q . && echo yes || echo no)"
check "this repo's copy has uses: lines to judge" "yes" "$(uses "$own" | grep -q . && echo yes || echo no)"

unpinned=$(uses "$tpl" | grep -Ev '^[^@ ]+@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$')
check "every uses: line in the template is a SHA pin with a version comment" "" "$unpinned"

# One persist-credentials: false per checkout, wherever the step puts `uses:`
# among its keys and however far it is indented.
checkouts=$(grep -c 'uses: *actions/checkout@' "$tpl")
persisted=$(grep -c '^ *persist-credentials: false *\(#.*\)\{0,1\}$' "$tpl")
check "every checkout in the template sets persist-credentials: false" "$checkouts" "$persisted"

check "this repo's claude-review.yml pins the refs its template does" \
  "$(uses "$tpl" | sort -u)" "$(uses "$own" | sort -u)"

finish
