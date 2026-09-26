#!/usr/bin/env bash
# Every pinned ref a skill states agrees with the ref this repo installed it at.
# A pin is stated twice over: as a `metadata.composes` entry,
# `<owner>/<repo>#<sha>:<skill>`, which ship's preflight installs from, and as a
# printed install line, `npx skills add <owner>/<repo>#<sha> --skill <name>...`,
# which setup-skills hands a human. Both must name the source and ref
# `skills-lock.json` records for that skill, because the lock is what this
# repo's runs actually tested. The `derived-copies` gate in scripts/local-gate.sh
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

# <file>: one `<skill>\t<source>\t<sha>` row per pin the file states. The
# composes read stops at the frontmatter's closing `---`, so a body line shaped
# like the key is prose.
pins() {
  awk 'NR>1 && /^---$/{exit} index($0, "  composes:") == 1 {
         for (i = 2; i <= NF; i++) { split($i, a, /[#:]/); print a[3] "\t" a[1] "\t" a[2] } }' "$1"
  awk '$1 == "npx" && $2 == "skills" && $3 == "add" && index($4, "#") {
         split($4, a, "#")
         for (i = 5; i < NF; i++) if ($i == "--skill") print $(i + 1) "\t" a[1] "\t" a[2] }' "$1"
}

rc=0
for f in "$root"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  rel=${f#"$root"/}
  while IFS=$'\t' read -r skill source sha; do
    got=$(jq -r --arg k "$skill" '.skills[$k] // {} | "\(.source // "none")#\(.ref // "none")"' "$lock") \
      || { printf 'cannot parse %s\n' "$lock" >&2; exit 2; }
    [ "$got" = "$source#$sha" ] && continue
    echo "pin drift: $skill is pinned at $source#$sha in $rel, the lock installed $got"
    rc=1
  done < <(pins "$f")
done
exit $rc
