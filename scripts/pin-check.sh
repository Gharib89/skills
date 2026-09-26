#!/usr/bin/env bash
# Every pinned ref a skill states agrees with the ref this repo installed it at.
# A pin is stated twice over: as a `metadata.composes` entry,
# `<owner>/<repo>#<sha>:<skill>`, which ship's preflight prints as the install
# line, and as a printed install line, `npx skills add <owner>/<repo>#<sha>
# --skill <name>...` at the start of a line of a skill's SKILL.md, which
# setup-skills hands a human. An install line with no `#<sha>` is read only for
# a skill the lock pins, so a pin a line lost is drift, while a line for a skill
# nothing pins (ship itself) is not a pin at all. Every pin must name the source
# and ref `skills-lock.json` records for that skill, because the lock is what
# this repo's runs actually tested. The `derived-copies` gate in scripts/local-gate.sh
# runs this, as one of its checks.
#
#   scripts/pin-check.sh [<root>]
#
# stdout: one line per pin that disagrees with the lock, nothing when all agree
# exit: 0 consistent · 1 drift · 2 tooling
set -uo pipefail
root=${1:-.}
lock=$root/skills-lock.json
[ -f "$lock" ] || { printf 'cannot read %s\n' "$lock" >&2; exit 2; }

# <file>: one `<skill>\t<source>\t<sha|none>\t<kind>` row per pin the file
# states, <kind> `printed` for an install line with no sha and `pin` otherwise.
# The composes line is read inside the frontmatter only, so a body line shaped
# like the key is prose.
pins() {
  awk 'function row(src, skill, bare,  h) {
         h = index(src, "#")
         if (h) print skill "\t" substr(src, 1, h - 1) "\t" substr(src, h + 1) "\tpin"
         else   print skill "\t" src "\tnone\t" bare }
       NR == 1 && /^---$/ { fm = 1; next }
       fm && /^---$/      { fm = 0; next }
       fm && index($0, "  composes:") == 1 {
         for (i = 2; i <= NF; i++) { n = split($i, a, ":"); row(substr($i, 1, length($i) - length(a[n]) - 1), a[n], "pin") } }
       !fm && $1 == "npx" && $2 == "skills" && $3 == "add" {
         for (i = 5; i < NF; i++) if ($i == "--skill") row($4, $(i + 1), "printed") }' "$1"
}

rc=0
for f in "$root"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  rel=${f#"$root"/}
  while IFS=$'\t' read -r skill source sha kind; do
    got=$(jq -r --arg k "$skill" '.skills[$k] // {} | "\(.source // "none")#\(.ref // "none")"' "$lock") \
      || { printf 'cannot parse %s\n' "$lock" >&2; exit 2; }
    [ "$kind" = printed ] && [ "${got##*#}" = none ] && continue
    [ "$got" = "$source#$sha" ] && [ "$sha" != none ] && continue
    echo "pin drift: $skill is pinned at $source#$sha in $rel, the lock installed $got"
    rc=1
  done < <(pins "$f")
done
exit $rc
