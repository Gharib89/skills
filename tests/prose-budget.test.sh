#!/usr/bin/env bash
# scripts/prose-budget-check.sh: the line budget on ship's prose. Each case
# builds a tree at the real relative paths under a fresh root, so a fixture
# differs from a tree inside the budget only in the overrun under test. The
# subject is the pair of thresholds and the `## Contents` selector: both
# boundaries, the first-15-lines anchor, the heading anchor, the empty glob and
# the path where the tooling itself fails.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <n>: n lines of body.
body() { local i=1; while [ "$i" -le "$1" ]; do printf 'line %s\n' "$i"; i=$((i + 1)); done; }

# <case>: a root with an in-budget skill; prints its path. Later helpers add to it.
tree() {
  local d="$fixture/$1"; rm -rf "$d"
  mkdir -p "$d/skills/ship/reference" || return 1
  body 10 > "$d/skills/ship/SKILL.md"
  printf '%s' "$d"
}
rc_of()  { bash scripts/prose-budget-check.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { bash scripts/prose-budget-check.sh "$1" 2>/dev/null; }

# The real tree, so prose that outgrows the budget fails a case here rather
# than leaving every synthetic fixture green.
check_rc "the current tree is inside the budget" 0 "$(rc_of .)"

d=$(tree at-400); body 400 > "$d/skills/ship/SKILL.md"
check_rc "a 400-line SKILL.md passes" 0 "$(rc_of "$d")"

d=$(tree over-400); body 401 > "$d/skills/ship/SKILL.md"
check_rc "a 401-line SKILL.md fails" 1 "$(rc_of "$d")"
check "the overrun message names the file and the count" \
  "skills/ship/SKILL.md: 401 lines, over the 400-line budget" "$(out_of "$d")"

d=$(tree at-100); body 100 > "$d/skills/ship/reference/r.md"
check_rc "a 100-line reference with no ## Contents passes" 0 "$(rc_of "$d")"

d=$(tree over-100); body 101 > "$d/skills/ship/reference/r.md"
check_rc "a 101-line reference with no ## Contents fails" 1 "$(rc_of "$d")"
check "the reference message names the file and the count" \
  'skills/ship/reference/r.md: 101 lines and no `## Contents` heading in its first 15 lines' \
  "$(out_of "$d")"

d=$(tree over-100-listed); { printf '# R\n\n## Contents\n\n'; body 97; } > "$d/skills/ship/reference/r.md"
check_rc "a 101-line reference with ## Contents passes" 0 "$(rc_of "$d")"

# Field-versus-line anchoring: the list has to be at the top, where a reader
# lands. A file whose ## Contents sits below the fold reads as navigable to a
# grep of the whole file and is not.
d=$(tree contents-late); { body 15; printf '## Contents\n'; body 90; } > "$d/skills/ship/reference/r.md"
check_rc "## Contents on line 16 is too late" 1 "$(rc_of "$d")"

# Heading anchor: `##` at the start of the line, and the line is the heading.
d=$(tree contents-not-heading)
{ printf -- '- see ## Contents below\n### Contents\n'; body 99; } > "$d/skills/ship/reference/r.md"
check_rc "a mention of ## Contents is not the heading" 1 "$(rc_of "$d")"

# Both budgets in one tree: the run reports every overrun, never the first.
d=$(tree both); body 401 > "$d/skills/ship/SKILL.md"; body 101 > "$d/skills/ship/reference/r.md"
check "both overruns are reported" \
  "skills/ship/SKILL.md: 401 lines, over the 400-line budget
skills/ship/reference/r.md: 101 lines and no \`## Contents\` heading in its first 15 lines" \
  "$(out_of "$d")"

# The empty glob: a skill with no reference directory is not an overrun.
d=$(tree no-reference); rmdir "$d/skills/ship/reference"
check_rc "a skill with no reference directory passes" 0 "$(rc_of "$d")"

# The tooling path: a root that is not there answers 2, not a vacuous 0 on a
# tree whose files no glob matched.
check_rc "a root that does not exist is tooling" 2 "$(rc_of "$fixture/absent")"

# The other tooling path: a file the glob matched and awk could not read. Root
# reads it anyway, so the case only runs where the mode bits bind.
if [ "$(id -u)" != 0 ]; then
  d=$(tree unreadable); chmod 000 "$d/skills/ship/SKILL.md"
  check_rc "a file that cannot be read is tooling" 2 "$(rc_of "$d")"
  chmod 644 "$d/skills/ship/SKILL.md"
fi

finish
