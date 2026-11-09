#!/usr/bin/env bash
# The PR body collapses its long sections on GitHub only (#1121). The rule is
# prose an agent follows, so each clause is pinned by the sentence that states
# it, and each is also run against its negation, which the matcher must refuse.
# The mechanics half proves a wrapped section is an ordinary section to them:
# its heading, its neighbours and a later rewrite are unaffected.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

section=$(awk '/^## Collapsing long sections/{f=1; next} /^## /{f=0} f' skills/ship/reference/pr-body.md | tr '\n' ' ' | tr -s ' ')
has() { grep -qiF -- "$2" <<<"$1" && echo yes || echo no; }

# <case>|<clause the section must hold>|<the clause with its meaning negated>
rules=(
  "GitHub wraps the long part of Review and Verification|On a GitHub host, the long part of \`## Review\` and \`## Verification\` goes inside a column-0 \`<details>\` block with a one-line \`<summary>\`|On a GitHub host, the long part of \`## Review\` and \`## Verification\` stays expanded"
  "the heading, exit word and one-line entries stay visible|The \`## \` heading, the exit word and any one-line entry stay outside the block|The \`## \` heading, the exit word and any one-line entry go inside the block"
  "Why the change and the Door line are never wrapped|\`## Why the change\` and the Door line are never wrapped|\`## Why the change\` and the Door line are wrapped"
  "a wrapped section is written once|Write a wrapped section once, in the write that finishes it|Write a wrapped section again with every round"
  "Azure DevOps keeps plain text|On an Azure DevOps host, write no \`<details>\` block|On an Azure DevOps host, write a \`<details>\` block"
)
for r in "${rules[@]}"; do
  IFS='|' read -r name clause negated <<<"$r"
  check "$name" yes "$(has "$section" "$clause")"
  check "$name: the negated clause is refused" no "$(has "$negated" "$clause")"
done

# A wrapped Review section: written, read back and rewritten by the mechanics.
review=$(mktemp); one=$(mktemp); trap 'rm -f "$review" "$one"' EXIT
cat > "$review" <<'WRAP'
- codex: reviewed, 1 finding fixed
<details>
<summary>codex round 1 details</summary>

## not a section: inside a record

Findings:
- P2 a finding

</details>
WRAP
printf -- '- codex: not reviewed: inline lane\n' > "$one"
body=$(cat <<'BODY'
Closes #1

## Why the change

why

## Special things to note

- 🟢 Door: two-way. Blast radius: none.

## Review

placeholder

## Attribution

footer
BODY
)
out=$(ship_body_replace_section "$body" Review "$review")
want=$'Why the change\nSpecial things to note\nReview\nAttribution'
check "a wrapped section leaves the headings unchanged" "$want" "$(ship_body_headings "$out")"
check "the Door line stays outside any details block" "no" "$(awk '/^<details/{d=1} /Door:/{print (d?"yes":"no")}' <<<"$out")"
check "the exit word stays above the block" "- codex: reviewed, 1 finding fixed" "$(awk '/^## Review/{f=1;next} f&&NF{print;exit}' <<<"$out")"
out2=$(ship_body_replace_section "$out" Review "$one")
# The reason for "written once": a section write keeps the old section's
# `<details>` records verbatim below the new content, so a second write of a
# wrapped section leaves the first block behind.
check "a later rewrite keeps the old block below the new content" "yes" "$(has "$out2" '<details>')"
check "and keeps the headings" "$want" "$(ship_body_headings "$out2")"

finish
