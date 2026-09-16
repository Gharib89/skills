#!/usr/bin/env bash
# The profile schema number lives in three files, and the bump rule in
# skills/setup-skills/profile-schema.md moves all three together: the `Schema:`
# line of the profile template, `metadata.profile-schema` in ship's SKILL.md,
# and the `## Schema <n>` entry in the schema doc. Why that rule needs a gate is
# in docs/agents/ship.md, under `## Local gate`. The `derived-copies` gate in
# scripts/local-gate.sh is this.
#
#   scripts/profile-schema-check.sh [<root>]
#
# Each read stops at the first body heading, so an example line further down the
# same file cannot feed a second value into the comparison, and the doc lookup
# is an exact fixed line, so a titled heading is not the entry.
#
# stdout: one line naming all three values when they disagree, nothing when they agree
# exit: 0 consistent · 1 drift · 2 tooling
set -uo pipefail
root=${1:-.}
tmpl=$root/skills/setup-skills/ship-profile.md
ship=$root/skills/ship/SKILL.md
doc=$root/skills/setup-skills/profile-schema.md
for f in "$tmpl" "$ship" "$doc"; do
  [ -f "$f" ] || { printf 'not a file: %s\n' "$f" >&2; exit 2; }
done

tmpl_schema=$(awk '/^## /{exit} /^Schema: /{print $2; exit}' "$tmpl")
ship_schema=$(awk '/^# /{exit} /^  profile-schema: /{print $2; exit}' "$ship")
doc_entry=missing
grep -qxF "## Schema $ship_schema" "$doc" && doc_entry=present
[ "$tmpl_schema" = "$ship_schema" ] && [ "$doc_entry" = present ] && exit 0
echo "profile schema drift: ship-profile.md declares Schema ${tmpl_schema:-none}," \
     "ship reads profile-schema ${ship_schema:-none}," \
     "profile-schema.md entry '## Schema ${ship_schema:-none}' $doc_entry"
exit 1
