#!/usr/bin/env bash
# scripts/profile-schema-check.sh: the profile schema number across three files.
# Each case builds a three-file tree at the real relative paths under a fresh
# root, so a fixture differs from a consistent tree only in the drift under
# test. The selectors are the subject: two awk field-versus-heading anchors and
# one exact-line grep, each with the input that reads as correct and answers
# wrong.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <schema>: the profile template, its `Schema:` line above the first heading.
tmpl_file() { printf '# Ship profile\n\nSchema: %s\n\n## Host\n\nHost: github\n' "$1"; }
# <schema>: ship's SKILL.md, frontmatter then a body.
ship_file() { printf -- '---\nname: ship\nmetadata:\n  version: 5.0.1\n  profile-schema: %s\n---\n\n# ship\n\nprose\n' "$1"; }
# <entry>...: the schema doc, one `## Schema <n>` heading per argument.
doc_file() { printf '# Profile schema\n\n'; printf '%s\n\n' "$@"; }

# <case> <tmpl> <ship> <doc>: a root holding the three files; prints its path.
tree() {
  local d="$fixture/$1"; rm -rf "$d"
  mkdir -p "$d/skills/setup-skills" "$d/skills/ship" || return 1
  printf '%s\n' "$2" > "$d/skills/setup-skills/ship-profile.md"
  printf '%s\n' "$3" > "$d/skills/ship/SKILL.md"
  printf '%s\n' "$4" > "$d/skills/setup-skills/profile-schema.md"
  printf '%s' "$d"
}
rc_of()  { bash scripts/profile-schema-check.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { bash scripts/profile-schema-check.sh "$1" 2>/dev/null; }

# The real tree, so a format change in the three files it reads fails a case
# here rather than leaving every synthetic fixture green.
check_rc "the current tree agrees" 0 "$(rc_of .)"

check_rc "all three agree" 0 \
  "$(rc_of "$(tree agree "$(tmpl_file 2)" "$(ship_file 2)" "$(doc_file '## Schema 1' '## Schema 2')")")"

# The drift PR #165 shipped: ship moved and the template did not.
behind=$(tree behind "$(tmpl_file 1)" "$(ship_file 2)" "$(doc_file '## Schema 1' '## Schema 2')")
check_rc "the template behind ship is drift" 1 "$(rc_of "$behind")"
check "the drift message names all three values" \
  "profile schema drift: ship-profile.md declares Schema 1, ship reads profile-schema 2, profile-schema.md entry '## Schema 2' present" \
  "$(out_of "$behind")"

check_rc "ship's number with no doc entry is drift" 1 \
  "$(rc_of "$(tree no-entry "$(tmpl_file 2)" "$(ship_file 2)" "$(doc_file '## Schema 1')")")"

# Field-versus-line anchoring: ship's SKILL.md documents the key in its own
# body, so the read stops at the first body heading and the frontmatter value
# is the only one that counts.
check_rc "a second profile-schema line in the body is ignored" 0 \
  "$(rc_of "$(tree body-line "$(tmpl_file 2)" \
    "$(ship_file 2)$(printf 'more prose\n  profile-schema: 9\n')" \
    "$(doc_file '## Schema 1' '## Schema 2')")")"

# The frontmatter value is what stops that read, so drop it: with no key above
# the first heading the body line is the only candidate, and the value is none.
# Without this case the one above passes whatever the heading anchor does.
check_rc "a body line is not read when the frontmatter has none" 1 \
  "$(rc_of "$(tree body-only "$(tmpl_file 2)" \
    "$(printf -- '---\nname: ship\n---\n\n# ship\n\n  profile-schema: 2\n')" \
    "$(doc_file '## Schema 1' '## Schema 2')")")"

# A schema value carrying a regex metacharacter: the doc lookup is exact and
# fixed, so `2.` does not match the entry `## Schema 2x` a regex would.
check_rc "a regex metacharacter in the value does not match another entry" 1 \
  "$(rc_of "$(tree metachar "$(tmpl_file '2.')" "$(ship_file '2.')" "$(doc_file '## Schema 2x')")")"

# The doc's format is the bare heading. A titled one is the drift the exact
# match exists to catch, not a looser spelling of the entry.
check_rc "a titled Schema heading is not an entry" 1 \
  "$(rc_of "$(tree titled "$(tmpl_file 2)" "$(ship_file 2)" "$(doc_file '## Schema 2: the reviewer blocks')")")"

# The template's `Schema:` line belongs above the first heading. One moved
# below it is not the template's declaration, and is reported as none.
check_rc "a Schema line below a heading is not read" 1 \
  "$(rc_of "$(tree moved "$(printf '# Ship profile\n\n## Host\n\nSchema: 2\n')" \
    "$(ship_file 2)" "$(doc_file '## Schema 1' '## Schema 2')")")"

# A file missing under the root is the tooling path, not drift: the check has
# nothing to compare rather than something that disagrees.
missing=$(tree missing "$(tmpl_file 2)" "$(ship_file 2)" "$(doc_file '## Schema 2')")
rm -f "$missing/skills/ship/SKILL.md"
check_rc "a missing file under the root is tooling" 2 "$(rc_of "$missing")"

# The same path for a file that is there and cannot be read: the selector's own
# exit status is the only report of it, and an ignored one reads as a value of
# `none`, which is drift. A directory at the path rather than a chmod, so the
# case fails for the same reason whatever uid runs it.
unreadable=$(tree unreadable "$(tmpl_file 2)" "$(ship_file 2)" "$(doc_file '## Schema 2')")
rm -f "$unreadable/skills/setup-skills/profile-schema.md"
mkdir -p "$unreadable/skills/setup-skills/profile-schema.md"
check_rc "a file that cannot be read is tooling" 2 "$(rc_of "$unreadable")"

finish
