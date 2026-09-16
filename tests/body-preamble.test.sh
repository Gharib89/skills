#!/usr/bin/env bash
# ship_body_replace_preamble: the transformation behind `update-pr-body
# --preamble`. The preamble is everything above the first unfenced `## `
# heading, which is where this repo's standard puts the Shape fence and where
# `open-pr` puts the closing line; before #173 nothing under scripts/ could
# rewrite it, so an accepted body-shape finding could only be reported.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

new=$(mktemp); trap 'rm -f "$new"' EXIT

# The preamble is replaced and every section below it survives untouched.
printf 'a shape\nand its caption\n' > "$new"
body=$(cat <<'EOF'
Closes #76

old preamble

## Summary

a summary

## Review

a review
EOF
)
expected=$(cat <<'EOF'
a shape
and its caption

Closes #76

## Summary

a summary

## Review

a review
EOF
)
check "replaces the preamble and keeps every section" \
  "$expected" "$(ship_body_replace_preamble "$body" "$new")"

# A body with no heading is all preamble, so the whole body is replaced.
check "replaces the whole body when it has no heading" \
  "$(printf 'a shape\nand its caption')" "$(ship_body_replace_preamble "just prose" "$new")"

# A body that opens on its first heading has an empty preamble. There is nothing
# to replace, and the content is still placed above that heading.
check "writes a preamble a body did not have" \
  "$(printf 'a shape\nand its caption\n\n## Summary\n\nbody')" \
  "$(ship_body_replace_preamble "$(printf '## Summary\n\nbody')" "$new")"

# The fence rule every transformation here reads: a `## ` inside a fence is
# example text, so it is not the boundary and the fenced block is not preamble.
fenced=$(cat <<'EOF'
old preamble

```diff
## not a heading
```

## Summary

a summary
EOF
)
expected=$(cat <<'EOF'
a shape
and its caption

## Summary

a summary
EOF
)
check "a fenced ## is not the boundary" "$expected" "$(ship_body_replace_preamble "$fenced" "$new")"

# The host returns a body with CRLF line endings; the boundary match is the
# column-0 `^## ` the section helper and `_gh_add_closes` read, which a CR at
# the end of the line does not disturb.
crlf_body=$(printf 'old preamble\r\n\r\n## Summary\r\n\r\na summary\r\n')
check "a CRLF heading is still the boundary" \
  "$(printf 'a shape\nand its caption\n\n## Summary\r\n\r\na summary\r')" \
  "$(ship_body_replace_preamble "$crlf_body" "$new")"

# `open-pr` puts `Closes #<issue>` in the preamble precisely so no section
# rewrite reaches it. A preamble rewrite does reach it, so a closing line the
# new content lacks is carried over, where open-pr puts it.
printf 'a shape\n' > "$new"
check "carries a closing line the new content lacks" \
  "$(printf 'a shape\n\nCloses #76\n\n## Summary\n\na summary')" \
  "$(ship_body_replace_preamble "$(printf 'Closes #76\n\n## Summary\n\na summary')" "$new")"

check "carries the closing line of a body with no heading" \
  "$(printf 'a shape\n\nFixes #76')" \
  "$(ship_body_replace_preamble "$(printf 'old\n\nFixes #76')" "$new")"

# Any inflection the shared closing-keyword test recognizes, and a multi-issue
# run, is the same line: it is carried whole, not rebuilt.
check "carries a multi-issue closing line whole" \
  "$(printf 'a shape\n\nresolves #75, #81\n\n## Summary\n\ns')" \
  "$(ship_body_replace_preamble "$(printf 'resolves #75, #81\n\n## Summary\n\ns')" "$new")"

# A new preamble that already closes the issue is not doubled.
printf 'a shape\n\nCloses #76\n' > "$new"
check "does not double a closing line the new content carries" \
  "$(printf 'a shape\n\nCloses #76\n\n## Summary\n\na summary')" \
  "$(ship_body_replace_preamble "$(printf 'Closes #76\n\n## Summary\n\na summary')" "$new")"

# A closing keyword quoted inside a fence is a mention, not a claim, the way
# ship_body_closes reads it: there is nothing to carry over.
printf 'a shape\n' > "$new"
check "a fenced closing keyword is not carried" \
  "$(printf 'a shape\n\n## Summary\n\ns')" \
  "$(ship_body_replace_preamble "$(printf '```\nCloses #76\n```\n\n## Summary\n\ns')" "$new")"

# A closing keyword inside a code span is a mention too, the way ship_body_closes
# reads one: the span comes out before the line is tested.
check "a closing keyword in a code span is not carried" \
  "$(printf 'a shape\n\n## Summary\n\ns')" \
  "$(ship_body_replace_preamble "$(printf 'the phrase `Closes #76` is quoted here\n\n## Summary\n\ns')" "$new")"

# A span that opens on one line and closes on a later one is one span, so the
# line inside it is quoted text: carrying it over would lift a quoted `Closes`
# out of its span and make it a real one.
printf 'a shape\n' > "$new"
check "a closing keyword in a multi-line code span is not carried" \
  "$(printf 'a shape\n\n## Summary\n\ns')" \
  "$(ship_body_replace_preamble "$(printf 'the phrase `text\nCloses #76\n` is quoted\n\n## Summary\n\ns')" "$new")"

# And the real line under such a span is still the one carried, rather than the
# quoted line above it winning by being first.
check "a real closing line under a multi-line span is the one carried" \
  "$(printf 'a shape\n\nCloses #173\n\n## Summary\n\ns')" \
  "$(ship_body_replace_preamble "$(printf '`text\nCloses #76\n`\nCloses #173\n\n## Summary\n\ns')" "$new")"

# An empty preamble file with a closing line to carry leaves no leading blank.
: > "$new"
check "an empty new preamble is just the carried line" \
  "$(printf 'Closes #76\n\n## Summary\n\ns')" \
  "$(ship_body_replace_preamble "$(printf 'Closes #76\n\n## Summary\n\ns')" "$new")"

finish
