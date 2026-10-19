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
# does: a folded or literal block's lines joined by one space, a quoted value
# without its quotes. Sizes are characters, not bytes, under any locale.
#
# stdout: `<source>: <n> chars` or `<source>: absent` per source, then
#         `total: <n> chars`
# stderr: on tooling, the reason
# exit: 0 a report · 2 tooling (no readable lock, an owned skill's SKILL.md
#       missing)
set -uo pipefail

die() { echo "context-report: $*" >&2; exit 2; }

root=${1:-.}
[ -d "$root" ] || die "not a directory: $root"
names=$(jq -r '.skills | to_entries[] | select(.value.source == ".") | .key' "$root/skills-lock.json") \
  || die "cannot read $root/skills-lock.json"

# Characters under any locale: the cloud sandbox runs with LANG and LC_ALL
# empty, where a shell's own length counts bytes, so drop UTF-8 continuation
# bytes before counting.
chars() { local n; n=$(LC_ALL=C tr -d '\200-\277' | wc -c) || exit 2; echo $((n)); }

# <file>: the frontmatter `description`, its indented continuation lines joined
# with one space.
description() {
  awk 'NR == 1 { if ($0 != "---") exit; next }
       $0 == "---" { exit }
       /^description:/ { on = 1; v = substr($0, 13); sub(/^[ \t]+/, "", v); if (v ~ /^[>|][-+0-9]*$/) v = ""; next }
       on && /^[ \t]/ { l = $0; sub(/^[ \t]+/, "", l); v = (v == "" ? l : v " " l); next }
       /^[^ \t]/ { on = 0 }
       END { if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2); printf "%s", v }' "$1"
}

total=0
# <label> <count>
line() { echo "$1: $2 chars"; total=$((total + $2)); }

for f in CLAUDE.md AGENTS.md; do
  if [ -r "$root/$f" ]; then line "$f" "$(chars < "$root/$f")"; else echo "$f: absent"; fi
done
while IFS= read -r n; do
  [ -n "$n" ] || continue
  [ -r "$root/skills/$n/SKILL.md" ] || die "cannot read skills/$n/SKILL.md"
  line "skills/$n" "$(description "$root/skills/$n/SKILL.md" | chars)"
done <<<"$names"
echo "total: $total chars"
