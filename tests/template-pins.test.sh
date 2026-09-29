#!/usr/bin/env bash
# The GitHub Actions a setup-skills reviewer template installs in a consumer:
# every `uses:` pins a 40-hex commit SHA with a `# vX.Y.Z` comment, because
# setup-harness wires zizmor whose `unpinned-uses` fails on a tag ref; every
# `actions/checkout` step sets `persist-credentials: false`, because no template
# step pushes; and this repo's own claude-review.yml, a copy of the template,
# pins no ref the template does not. The two reads are functions so the fixture
# cases can break them. Reads files only; no call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

tpl=skills/setup-skills/reviewers/github-claude-review.md
own=.github/workflows/claude-review.yml

uses() { sed -n 's/^ *\(- *\)\{0,1\}uses: *//p' "$1"; }

# Prints each `uses:` value that is not `<action>@<40-hex> # vX.Y.Z`.
unpinned() { uses "$1" | grep -Ev '^[^@ ]+@[0-9a-f]{40} # v[0-9]+\.[0-9]+\.[0-9]+$'; }

# Prints the line of each checkout step lacking its own persist-credentials:
# false. A step is a blank-line-separated paragraph, so a key in another step or
# in prose never counts for this one.
unpersisted() {
  awk 'BEGIN { RS = "" }
       /uses: *actions\/checkout@/ && !/(^|\n) *persist-credentials: false *(#[^\n]*)?(\n|$)/ {
         n = split($0, l, "\n"); for (i = 1; i <= n; i++) if (l[i] ~ /uses: *actions\/checkout@/) print l[i]
       }' "$1"
}

sha=0123456789abcdef0123456789abcdef01234567
fx=$(mktemp -d) || exit 2
trap 'rm -rf "$fx"' EXIT
mk() { printf '%s\n' "$2" > "$fx/$1"; }

mk good "      - uses: actions/checkout@$sha # v7.0.1
        with:
          fetch-depth: 1
          persist-credentials: false
"
mk other-step "      - uses: actions/checkout@$sha # v7.0.1
        with:
          fetch-depth: 1

      - uses: someone/else@$sha # v1.0.0
        with:
          persist-credentials: false
"
mk prose-only "Set \`persist-credentials: false\` on the checkout.

      - uses: actions/checkout@$sha # v7.0.1
        with:
          fetch-depth: 1
"
mk name-first "      - name: Check out
        uses: actions/checkout@$sha # v7.0.1
        with:
          persist-credentials: false

      - name: Check out again
        uses:   actions/checkout@$sha # v7.0.1
        with:
          fetch-depth: 1
"
mk tag-pin "      - uses: actions/checkout@v7
      - uses: actions/checkout@$sha
      - uses: actions/checkout@0123456789ABCDEF0123456789ABCDEF01234567 # v7.0.1
"
: > "$fx/empty"

check "a checkout carrying its key is judged persisted" "" "$(unpersisted "$fx/good")"
check "a key in another step does not persist this checkout" \
  "      - uses: actions/checkout@$sha # v7.0.1" "$(unpersisted "$fx/other-step")"
check "a key in prose does not persist a checkout" \
  "      - uses: actions/checkout@$sha # v7.0.1" "$(unpersisted "$fx/prose-only")"
check "a name-first, re-spaced checkout without the key is caught" \
  "        uses:   actions/checkout@$sha # v7.0.1" "$(unpersisted "$fx/name-first")"
check "a file with no checkout has none unpersisted" "" "$(unpersisted "$fx/empty")"

check "a SHA pin with a version comment is pinned" "" "$(unpinned "$fx/good")"
check "a tag, a bare SHA and an uppercase SHA are each unpinned" \
  "actions/checkout@v7
actions/checkout@$sha
actions/checkout@0123456789ABCDEF0123456789ABCDEF01234567 # v7.0.1" "$(unpinned "$fx/tag-pin")"

# A file that vanished or lost its steps passes every case below on empty
# output, so each must yield at least one ref before it is judged.
check "the template has uses: lines to judge" "yes" "$(uses "$tpl" | grep -q . && echo yes || echo no)"
check "this repo's copy has uses: lines to judge" "yes" "$(uses "$own" | grep -q . && echo yes || echo no)"

check "every uses: line in the template is a SHA pin with a version comment" "" "$(unpinned "$tpl")"
check "every checkout in the template sets persist-credentials: false" "" "$(unpersisted "$tpl")"

# Refs only the copy carries: a ref the template lacks is drift, while a template
# ref the copy does not use (the copy installs one of the template's two shapes)
# is not.
check "this repo's claude-review.yml pins no ref its template does not" "" \
  "$(comm -13 <(uses "$tpl" | sort -u) <(uses "$own" | sort -u))"

finish
