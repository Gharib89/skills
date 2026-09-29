#!/usr/bin/env bash
# The GitHub Actions a setup-skills reviewer template installs in a consumer:
# every `uses:` pins a 40-hex commit SHA with a `# vX.Y.Z` comment, because
# setup-harness wires zizmor whose `unpinned-uses` fails on a major tag; every
# `actions/checkout` sets `persist-credentials: false`, because no template
# step pushes; and this repo's own claude-review.yml, a copy of the template,
# pins the same refs. Reads files only; no call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

tpl=skills/setup-skills/reviewers/github-claude-review.md
own=.github/workflows/claude-review.yml

uses() { sed -n 's/^ *\(- \)\{0,1\}uses: *//p' "$1"; }

unpinned=$(uses "$tpl" | grep -Ev '^[^@ ]+@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$')
check "every uses: line in the template is a SHA pin with a version comment" "" "$unpinned"

# One checkout step per workflow block; each must be followed, before the next
# `- ` step, by a persist-credentials: false line.
missing=$(awk '
  /^ *- uses: actions\/checkout@/ { if (open) print open; open = NR; next }
  /^ *persist-credentials: false$/ { open = 0; next }
  /^      - / { if (open) print open; open = 0 }
  END { if (open) print open }
' "$tpl")
check "every checkout in the template sets persist-credentials: false" "" "$missing"

check "this repo's claude-review.yml pins the refs its template does" \
  "$(uses "$tpl" | sort -u)" "$(uses "$own" | sort -u)"

finish
