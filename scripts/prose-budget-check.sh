#!/usr/bin/env bash
# The prose budget on ship's own documents. A run reads SKILL.md top to bottom
# at load, so a file that outgrows its budget buries the pipeline behind its own
# reference material, and a reference file long enough to scroll needs a map at
# the top rather than at the point a reader gives up. The thresholds and the
# paths, whole: `skills/*/SKILL.md` at most 400 lines, and every
# `skills/*/reference/*.md` over 100 lines opening with a `## Contents` heading
# inside its first 15 lines. The `prose-budget` gate in scripts/local-gate.sh
# runs this, in every lane.
#
#   scripts/prose-budget-check.sh [<root>]
#
# stdout: one line per file over budget, nothing when every file is inside it
# exit: 0 inside the budget · 1 over it · 2 tooling
set -uo pipefail
root=${1:-.}
[ -d "$root" ] || { printf 'not a directory: %s\n' "$root" >&2; exit 2; }
shopt -s nullglob

# awk reports an unreadable file in its exit status, and an ignored status turns
# that into a count of nothing and a budget answer about a file nobody read.
lines() { awk 'END{print NR}' "$1"; }

# One awk rather than `head | grep`, because this script runs under pipefail: a
# SIGPIPE on the head of that pipeline would read as a file without the heading.
# Both `exit`s run END, so the status comes from `f` either way.
#
# A `## Contents` line inside a fenced example is example text, so the scan
# tracks fences, in the grammar `SHIP_AWK_FENCE` in skills/ship/scripts/_lib.sh
# states in full: three or more backticks or tildes under up to three spaces
# open a fence, and only a bare run of the same character at least as long
# closes it. This is a second copy of that grammar because a local gate never
# sources `_lib.sh`, which serves ship's mechanics alone; the tilde, long-run
# and indented cases in tests/prose-budget.test.sh are what hold the copy to it.
has_contents() {
  awk '
    NR>15{exit}
    {
      s = $0; sub(/^ ? ? ?/, "", s); c = substr(s, 1, 1)
      if (c == "`" || c == "~") {
        n = 0; while (substr(s, n + 1, 1) == c) n++
        if (n >= 3) {
          if (!fenced) {
            if (!(c == "`" && index(substr(s, n + 1), "`"))) {
              fenced = 1; fchar = c; flen = n
            }
          }
          else if (c == fchar && n >= flen && substr(s, n + 1) ~ /^[ \t\r]*$/) fenced = 0
          next
        }
      }
    }
    !fenced && $0 == "## Contents"{f = 1; exit}
    END{exit !f}
  ' "$1"
}

rc=0
for f in "$root"/skills/*/SKILL.md; do
  n=$(lines "$f") || { printf 'cannot read %s\n' "$f" >&2; exit 2; }
  [ "$n" -le 400 ] \
    || { printf '%s: %s lines, over the 400-line budget\n' "${f#"$root"/}" "$n"; rc=1; }
done
for f in "$root"/skills/*/reference/*.md; do
  n=$(lines "$f") || { printf 'cannot read %s\n' "$f" >&2; exit 2; }
  [ "$n" -gt 100 ] || continue
  has_contents "$f" && continue
  printf '%s: %s lines and no `## Contents` heading in its first 15 lines\n' \
    "${f#"$root"/}" "$n"
  rc=1
done
exit $rc
