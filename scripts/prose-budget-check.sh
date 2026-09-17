#!/usr/bin/env bash
# The prose budget on ship's own documents. A run reads SKILL.md top to bottom
# at load, so a file that outgrows its budget buries the pipeline behind its own
# reference material, and a reference file long enough to scroll needs a map at
# the top rather than at the point a reader gives up. The thresholds and the
# paths, whole: `skills/*/SKILL.md` at most 400 lines, and every
# `skills/*/reference/*.md` over 100 lines opening with a `## Contents` heading
# inside its first 15 lines whose list matches the file's `## ` headings. The
# `prose-budget` gate in scripts/local-gate.sh runs this, in every lane.
#
#   scripts/prose-budget-check.sh [<root>]
#
# stdout: one line per violation, nothing when every file is inside the budget
# exit: 0 inside the budget · 1 over it · 2 tooling
set -uo pipefail
root=${1:-.}
[ -d "$root" ] || { printf 'not a directory: %s\n' "$root" >&2; exit 2; }
shopt -s nullglob

# awk reports an unreadable file in its exit status, and an ignored status turns
# that into a count of nothing and a budget answer about a file nobody read.
lines() { awk 'END{print NR}' "$1"; }

# One awk over the whole file rather than `head | grep`, because this script runs
# under pipefail: a SIGPIPE on the head of that pipeline would read as a file
# without the heading. It answers both halves of the budget's `## Contents` rule,
# so the fence grammar below is stated once.
#
# A `## Contents` line inside a fenced example is example text, so the scan
# tracks fences, in the grammar `SHIP_AWK_FENCE` in skills/ship/scripts/_lib.sh
# states in full: three or more backticks or tildes under up to three spaces
# open a fence, and only a bare run of the same character at least as long
# closes it, with one asymmetry: a backtick run carrying another backtick after
# it is an info string CommonMark disallows, so the line is paragraph text and
# opens nothing. This is a second copy of that grammar because a local gate never
# sources `_lib.sh`, which serves ship's mechanics alone; the tilde, long-run
# and indented cases in tests/prose-budget.test.sh are what hold the copy to it.
#
# The second half is the list itself: a map that does not match the file sends a
# reader to a heading that is not there, which is worse than no map, so every
# `## ` heading has an entry and every entry names a heading. The list is the run
# of list items directly under the heading, blank lines included and the first
# other line, a fence delimiter among them, ending it, so a bullet in the prose
# below is prose. An item is one at the same up-to-three-space indent the fence
# grammar allows: four spaces open an indented code block, so an example list in
# the section is not the map, and a deeper item is a sub-list, which is neither an
# entry nor the end of the list. An entry names a heading when its bracketed link text, or its
# whole text where the `](` is not there to make it a link, equals the heading;
# both sides are trimmed at both ends, so padding and a CRLF line ending, neither
# of them visible in the file a reader compares the list against, are neither.
#
#   contents_check <file> <display-name> <line-count>
#
# stdout: one line per violation · exit: 0 clean · 1 a `## Contents` violation
contents_check() {
  awk -v name="$2" -v count="$3" '
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
          listing = 0
          next
        }
      }
      if (fenced) next
      if ($0 ~ /^## /) {
        h = substr($0, 4); sub(/^[ \t]+/, "", h); sub(/[ \t\r]+$/, "", h)
        if (h == "Contents") { if (NR <= 15) anchored = 1; listing = 1; next }
        listing = 0; heads[h] = 1; horder[++nh] = h
        next
      }
      if (listing) {
        if ($0 ~ /^[ \t\r]*$/) next
        if (s ~ /^([-*+]|[0-9]+\.)[ \t]+/) {
          e = s
          sub(/^([-*+]|[0-9]+\.)[ \t]+/, "", e); sub(/[ \t\r]+$/, "", e)
          if (match(e, /^\[[^]]*\]\(/)) {
            e = substr(e, RSTART + 1, RLENGTH - 3)
            sub(/^[ \t]+/, "", e); sub(/[ \t]+$/, "", e)
          }
          ents[e] = 1; eorder[++ne] = e
          next
        }
        if ($0 ~ /^[ \t]+([-*+]|[0-9]+\.)[ \t]+/) next
        listing = 0
      }
    }
    END{
      if (!anchored) {
        printf "%s: %s lines and no `## Contents` heading in its first 15 lines\n", name, count
        exit 1
      }
      for (i = 1; i <= nh; i++)
        if (!(horder[i] in ents)) {
          printf "%s: `## %s` has no entry under `## Contents`\n", name, horder[i]; bad = 1
        }
      for (i = 1; i <= ne; i++)
        if (!(eorder[i] in heads)) {
          printf "%s: `## Contents` entry `%s` names no heading\n", name, eorder[i]; bad = 1
        }
      exit bad
    }
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
  contents_check "$f" "${f#"$root"/}" "$n" || rc=1
done
exit $rc
