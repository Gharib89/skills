#!/usr/bin/env bash
# Context report: the size of the always-on context this repo owns.
#
# The root CLAUDE.md, the root AGENTS.md and the `description` of each skill
# this repo writes load into every session that reaches them, so growth in any
# of them is a cost every run pays. Nothing else reports it, and a total alone
# hides which source grew, so this prints one line per source. It is a report,
# never a gate: there is no cap, so nothing here can fail a PR.
#
#   scripts/context-report.sh [<root>]      <root> defaults to the current directory
#
# Sources: the root `CLAUDE.md` and `AGENTS.md` (a missing one prints `absent`),
# and `skills/<name>/SKILL.md`'s `description` for every `skills-lock.json`
# entry whose `source` is `.`. Vendored skills and anything outside the checkout
# (`~/.claude`) are never read, so the report is the same on every machine. A
# description counts as the agent reads it, as scripts/frontmatter-check.sh
# does (a folded or literal block's lines joined by one space, a quoted value
# without its quotes); the reader below mirrors that script's for every input
# it accepts, so change both together. Sizes are characters, not bytes, under
# any locale.
#
# stdout: `<source>: <n> chars` or `<source>: absent` per source, then
#         `total: <n> chars`
# stderr: on tooling, the reason
# exit: 0 a report · 2 tooling (no readable lock, an owned skill's SKILL.md
#       missing, a count that failed)
set -uo pipefail

die() { echo "context-report: $*" >&2; exit 2; }

root=${1:-.}
[ -d "$root" ] || die "not a directory: $root"
names=$(jq -r '(.skills | if type == "object" then . else error("skills is not an object") end)
  | to_entries[] | select(.value.source == ".") | .key' "$root/skills-lock.json") \
  || die "cannot read $root/skills-lock.json"

# Characters under any locale: the cloud sandbox runs with LANG and LC_ALL
# empty, where a shell's own length counts bytes, so drop UTF-8 continuation
# bytes before counting.
chars() { local n; n=$(LC_ALL=C tr -d '\200-\277' | wc -c) || return 1; echo $((n)); }

# <file>: the frontmatter `description`, read as scripts/frontmatter-check.sh's
# `fields` reads it, for every input that script accepts: indented continuation
# lines joined with one space, a `#` comment after an unquoted value and
# trailing blanks dropped, a closed quote stripped, and a quote inside a `>` or
# `|` block left as text.
description() {
  awk 'function flush() {
         if (key == "description") {
           if (!block && v ~ /^["\047]/) {
             if (substr(v, 1, 1) == "\"") closed = match(v, /^"([^"\\]|\\.)*"/)
             else closed = match(v, "^\047([^\047]|\047\047)*\047")
             if (closed) v = substr(v, 2, RLENGTH - 2) }
           desc = v } }
       NR == 1 { if ($0 != "---") exit; next }
       $0 == "---" { exit }
       /^[^ \t#][^:]*:/ {
         flush()
         key = substr($0, 1, index($0, ":") - 1); val = substr($0, length(key) + 2)
         sub(/^[ \t]+/, "", val)
         if (val !~ /^["\047]/) sub(/[ \t]+#.*$/, "", val)
         sub(/[ \t]+$/, "", val)
         block = (val ~ /^[>|]([1-9]?[-+]?|[-+][1-9])$/); v = block ? "" : val
         next }
       /^[ \t]/ { line = $0; sub(/^[ \t]+/, "", line); v = (v == "" ? line : v " " line) }
       END { flush(); printf "%s", desc }' "$1"
}

total=0
# <label> <count>
line() { echo "$1: $2 chars"; total=$((total + $2)); }

for f in CLAUDE.md AGENTS.md; do
  if [ -r "$root/$f" ]; then
    c=$(chars < "$root/$f") || die "cannot count $f"
    line "$f" "$c"
  else
    echo "$f: absent"
  fi
done
while IFS= read -r n; do
  [ -n "$n" ] || continue
  [ -r "$root/skills/$n/SKILL.md" ] || die "cannot read skills/$n/SKILL.md"
  c=$(description "$root/skills/$n/SKILL.md" | chars) || die "cannot count skills/$n"
  line "skills/$n" "$c"
done <<<"$names"
echo "total: $total chars"
