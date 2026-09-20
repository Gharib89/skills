#!/usr/bin/env bash
# ship_triage_label: the role-to-label lookup, read from the role table the
# label file opens with and no further. Every case sources the function and
# runs it inside a fixture checkout under the OS temp dir, one of them carrying
# this repo's own label file; none reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# A fixture is a checkout, because the function resolves the label file from
# the main checkout: `git init` is what makes `ship_main_checkout` answer.
checkout() { # checkout <name>: prints the path of a checkout with no label file
  local d="$tmp/$1"
  mkdir -p "$d/docs/agents" && git init -q "$d" >/dev/null 2>&1 || return 1
  printf '%s' "$d"
}
fixture() { # fixture <name>: a checkout carrying the label file from stdin
  local d; d=$(checkout "$1") || return 1
  cat > "$d/docs/agents/triage-labels.md"
  printf '%s' "$d"
}
resolve() { (cd "$1" && ship_triage_label "$2"); }

# This repo's own file, resolved as a fixture: each role resolves to the same
# string after the bound as before it. The copy is what makes the case read the
# branch's rows, because the function resolves the file through
# `ship_main_checkout`, which answers with the main checkout and not the
# worktree a run works in.
d=$(fixture repo < docs/agents/triage-labels.md)
for role in needs-triage needs-info ready-for-agent ready-for-human wontfix; do
  check "this repo's label file resolves $role" "$role" "$(resolve "$d" "$role")"
done

# A dropped role row and a dimension row spelled like that role: the dimension
# table sits after the `## ` heading, so it is out of the bound and the lookup
# falls back to the canonical name instead of returning a colour.
md=$(cat <<'MD'
# Triage Labels

| Label in mattpocock/skills | Label in our tracker |
| -------------------------- | -------------------- |
| `needs-triage`             | `needs-triage`       |
| `ready-for-agent`          | `ready-for-agent`    |

Prose under the table.

## Dimension labels

### Size

| Label | Color | Description |
| --- | --- | --- |
| `needs-info` | `fbca04` | Small |
MD
)
d=$(printf '%s\n' "$md" | fixture dropped)
check "a dimension row spelled like a dropped role is not a role" \
  needs-info "$(resolve "$d" needs-info)"
check "a role still in the table resolves across that heading" \
  ready-for-agent "$(resolve "$d" ready-for-agent)"

# The bound is the first `## ` heading, not the word `Dimension`: a role row
# inside it wins over a same-spelling row after it.
md=$(cat <<'MD'
# Triage Labels

| Label in mattpocock/skills | Label in our tracker |
| -------------------------- | -------------------- |
| `ready-for-agent`          | `agent-ready`        |

## Dimension labels

### Kind

| Label | Type | Color | Description |
| --- | --- | --- | --- |
| `ready-for-agent` | `feat` | `a2eeef` | not a role |
MD
)
d=$(printf '%s\n' "$md" | fixture renamed)
check "the role table wins over a same-spelling row below the heading" \
  agent-ready "$(resolve "$d" ready-for-agent)"

# A file with no heading is all role table, which is what the lookup read
# before the bound.
md=$(cat <<'MD'
# Triage Labels

| Label in mattpocock/skills | Label in our tracker |
| -------------------------- | -------------------- |
| `wontfix`                  | `declined`           |
MD
)
d=$(printf '%s\n' "$md" | fixture headingless)
check "a file with no heading resolves as before" \
  declined "$(resolve "$d" wontfix)"

# The two fallbacks the bound leaves alone.
check "a role with no row falls back to the canonical name" \
  needs-triage "$(resolve "$d" needs-triage)"
check "a missing label file falls back to the canonical name" \
  ready-for-human "$(resolve "$(checkout empty)" ready-for-human)"

# The bound is the first `## ` heading wherever it sits, so a heading above the
# role table puts the whole table out of it and every role falls back. The
# template `setup-skills` writes opens with the table, which is what keeps this
# reachable only by editing the file out of shape.
md=$(cat <<'MD'
# Triage Labels

## Preamble

| Label in mattpocock/skills | Label in our tracker |
| -------------------------- | -------------------- |
| `wontfix`                  | `declined`           |
MD
)
d=$(printf '%s\n' "$md" | fixture heading-first)
check "a heading above the role table puts the table out of the bound" \
  wontfix "$(resolve "$d" wontfix)"

finish
