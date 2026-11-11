#!/usr/bin/env bash
# Grade statement: a PR whose diff can change the release grade says so in its
# body. The grade is the title's Conventional-Commit type, and only a reviewer
# checked it against the diff: #1131 titled `fix` a change that added a key to a
# mechanic's JSON, and #1077 and #1089 reworded a skill `description`, which
# adds a routing condition, with the body silent on the grade. Two diffs need a
# `Grade:` line under `## Special things to note`:
#
#   - a skill's `description` (the frontmatter of `skills/<name>/SKILL.md`,
#     the source tree only: a derived copy under `.claude/skills/` is the same
#     text, never a second change), whatever the title's type: the line says
#     whether a routing condition was added or dropped;
#   - a mechanic's usage line (`usage=`) or `stdout:` header block in
#     `skills/<name>/scripts/*.sh`, under a title whose type is not `feat`: the
#     line says why the change is a patch.
#
# The line present passes the check: it holds the author to stating the grade
# and leaves judging it to the reviewer. A description rewrapped with no change
# of words is no change. Every title type cuts at least a patch (release.md), so
# a `chore` title is no under-grade by number; the line is what a reviewer reads.
#
#   PR_TITLE=... PR_BODY=... PR_BASE=<ref> [PR_ROOT=<checkout>] scripts/check-grade-statement.sh
#
# PR_BASE is the ref the PR's diff counts from (the diff is `PR_BASE...HEAD`);
# PR_ROOT defaults to the checkout holding this script.
#
# stdout: one `grade-statement: ...` line per changed file naming the line to add
# exit: 0 no line owed, or present · 1 a line owed and absent · 2 tooling
set -uo pipefail

title=${PR_TITLE:-}
body=${PR_BODY:-}
base=${PR_BASE:-}
root=${PR_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
[ -n "$base" ] || { echo "check-grade-statement: PR_BASE is not set" >&2; exit 2; }
git -C "$root" rev-parse --verify -q "$base^{commit}" >/dev/null || { printf 'check-grade-statement: no such ref: %s\n' "$base" >&2; exit 2; }

changed=$(git -C "$root" diff --name-only "$base...HEAD") || exit 2

# <rev> <path>: the file at that revision, nothing when it is not there.
show() { git -C "$root" show "$1:$2" 2>/dev/null; }

# stdin: a SKILL.md; its frontmatter `description` on one line, whitespace
# collapsed and a block-scalar indicator dropped, so a rewrap compares equal.
description() {
  awk '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    /^description:/ { on = 1; sub(/^description:[ \t]*/, ""); d = $0; next }
    on && /^[ \t]/ { d = d " " $0; next }
    on { on = 0 }
    END { sub(/^[>|][+-]?[ \t]+/, "", d); gsub(/[ \t]+/, " ", d); sub(/^ /, "", d); print d }
  '
}
# stdin: a mechanic; its `usage=` lines and `# stdout:` header block (the
# comment lines after `# stdout:` up to `# exit:` or the first non-comment).
contract() {
  awk '
    /^usage=/ { print; next }
    /^# stdout:/ { on = 1; print; next }
    on && /^#/ && !/^# exit:/ && !/^#$/ { print; next }
    { on = 0 }
  '
}

desc_files='' mech_files=''
while IFS= read -r f; do
  case $f in
    skills/*/SKILL.md)
      case ${f#skills/} in */*/*) continue ;; esac
      [ "$(show "$base" "$f" | description)" = "$(show HEAD "$f" | description)" ] || desc_files="$desc_files$f"$'\n'
      ;;
    skills/*/scripts/*.sh)
      case ${f#skills/*/scripts/} in */*) continue ;; esac
      [ "$(show "$base" "$f" | contract)" = "$(show HEAD "$f" | contract)" ] || mech_files="$mech_files$f"$'\n'
      ;;
  esac
done <<EOF
$changed
EOF

type=${title%%[(:!]*}
[ "$type" = feat ] && mech_files=''

[ -n "$desc_files$mech_files" ] || { echo "grade-statement: no description or mechanic contract changed, no Grade: line owed."; exit 0; }

# A `Grade:` line, with its text, between the heading and the next `##`,
# outside an HTML comment, which renders as nothing.
stated=$(printf '%s\n' "$body" | awk '
  /^## / { on = ($0 ~ /^## Special things to note[ \t]*\r?$/); next }
  !on { next }
  { line = $0
    while (1) {
      if (cm) { i = index(line, "-->"); if (!i) { line = ""; break } line = substr(line, i + 3); cm = 0 }
      i = index(line, "<!--"); if (!i) break
      j = index(substr(line, i + 4), "-->")
      if (j) line = substr(line, 1, i - 1) substr(line, i + 4 + j + 2)
      else { line = substr(line, 1, i - 1); cm = 1; break }
    }
    if (line ~ /^[ \t]*([-*][ \t]+)?Grade:[ \t]*[^ \t\r]/) found = 1 }
  END { print found ? "yes" : "no" }')
[ "$stated" = yes ] && { echo "grade-statement: Grade: line present."; exit 0; }

while IFS= read -r f; do
  [ -n "$f" ] || continue
  printf 'grade-statement: %s changes the skill description; add a `Grade:` line under "## Special things to note" saying whether a routing condition was added or dropped, whatever the title'"'"'s type.\n' "$f"
done <<EOF
$desc_files
EOF
while IFS= read -r f; do
  [ -n "$f" ] || continue
  printf 'grade-statement: %s changes its usage line or `stdout:` header under a `%s` title; add a `Grade:` line under "## Special things to note" saying why the change is a patch.\n' "$f" "$type"
done <<EOF
$mech_files
EOF
exit 1
