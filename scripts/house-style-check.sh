#!/usr/bin/env bash
# The em-dash ban from docs/contributing/coding-standards.md, plus no trailing
# whitespace and a final newline on every non-empty file, over the files this
# repo authors, and an 80-column wrap width over the files it hard-wraps. A consumer repo's stock `trailing-whitespace` and
# `end-of-file-fixer` hooks fail on a copied script that breaks either (issue
# #288). `.claude/skills/` is install output from other repos and is exempt. The
# `house-style` gate in scripts/local-gate.sh runs this, in every lane.
#
# Build the dash from its UTF-8 bytes. A `$'\u2014'` escape expands by locale:
# with LANG and LC_ALL empty (the cloud sandbox) it stays literal escape text and
# matches this script's own source (issue #249). Bytes match under any locale.
#
#   scripts/house-style-check.sh
#
# stdout: the offending lines, and each file missing its final newline; nothing when clean
# stderr: on tooling, git's reason, at most 40 lines
# exit: 0 clean · 1 a finding · 2 tooling
set -uo pipefail

paths=('skills/*' 'docs/*' 'scripts/*' 'tests/*' '.github/*' '.release/*' GLOSSARY.md CLAUDE.md)
found=0
err=$(mktemp) || exit 2
trap 'rm -f "$err"' EXIT

# <git grep args...> over the tracked files. It reports an unreadable file on
# stderr and still exits 0 or 1, so anything on stderr is tooling. Every rule
# reads the same files, so the first rule's check covers the listing below.
repo_grep() { git grep "$@" -- "${paths[@]}" 2>"$err"; }
# Exit 2 with git's own reason on stderr, capped at 40 lines.
tooling() { tail -n 40 "$err" >&2; exit 2; }

# <heading> <git grep pattern args...>: prints the heading and the hits when any.
# 1 is a clean tree, and anything past 1, such as a run outside a checkout, is
# tooling rather than a clean answer.
grep_rule() {
  local heading=$1 hits rc
  shift
  hits=$(repo_grep -n "$@"); rc=$?
  [ -s "$err" ] && tooling
  case $rc in
    0) ;;
    1) return 0 ;;
    *) tooling ;;
  esac
  echo "$heading"
  echo "$hits"
  found=1
}

em=$(printf '\342\200\224')
grep_rule "em dashes in repo-authored files (see docs/contributing/coding-standards.md):" -F -e "$em"
grep_rule "trailing whitespace in repo-authored files:" -I -e '[[:blank:]]$'

# `-I -l -e ''` lists every text file with a line, which skips binaries,
# symlinks, empty files and files deleted in the worktree, as the stock
# end-of-file-fixer does. A last byte that is a newline is stripped by the
# substitution, leaving it empty.
missing=
while IFS= read -r -d '' f; do
  last=$(tail -c 1 -- "$f")
  [ -z "$last" ] || missing+="$f"$'\n'
done < <(repo_grep -z -I -l -e '')
if [ -n "$missing" ]; then
  echo "no final newline in repo-authored files:"
  printf '%s' "$missing"
  found=1
fi

# The files this repo hard-wraps at 80 columns. The rest of the tree puts one
# paragraph on a line (a profile's `Label:` line must stay one line), so a new
# hard-wrapped file joins this list. Exempt are changelogs, which the release
# run writes, and the lines no reflow shortens: frontmatter, fences, tables, and
# a line holding only a link, a code span or a link reference definition.
wrapped=('skills/ship/*.md' 'skills/cloud-ship/*.md' 'skills/update-skills/*.md'
  'skills/grill-with-artifact/*.md' docs/contributing/coding-standards.md CLAUDE.md
  ':!:*CHANGELOG.md')
files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(git grep -z -I -l -e '' -- "${wrapped[@]}" 2>"$err")
[ -s "$err" ] && tooling
# Columns are characters: under LC_ALL=C, dropping the UTF-8 continuation bytes
# leaves one byte per character, under any caller's locale.
too_wide=
[ "${#files[@]}" -eq 0 ] || too_wide=$(LC_ALL=C awk '
  FNR == 1 { fence = ""; front = ($0 == "---"); if (front) next }
  front { if ($0 == "---") front = 0; next }
  { t = $0; sub(/^[ \t]*/, "", t) }
  # A fence closes on a bare run of its own character, at least as long as the
  # opening run, as CommonMark has it; an unclosed one runs to the end. Indent
  # is not read: a fence inside a list item sits at the content column of the
  # item, past the three spaces CommonMark allows (the update-skills SKILL.md
  # nests one at five).
  fence != "" {
    if (t ~ /^(`+|~+)[ \t]*$/ && substr(t, 1, 1) == substr(fence, 1, 1)) {
      sub(/[ \t]*$/, "", t)
      if (length(t) >= length(fence)) fence = ""
    }
    next
  }
  t ~ /^(```|~~~)/ {
    fence = t
    if (substr(t, 1, 1) == "`") sub(/[^`].*$/, "", fence); else sub(/[^~].*$/, "", fence)
    next
  }
  t ~ /^\|/ { next }
  /^[ \t]*([-*+]|[0-9]+\.)?[ \t]*(\[[^]]*\]\([^ )]*\)|`[^`]*`)[.,;:]?$/ || /^[ \t]*\[[^]]*\]:[ \t]/ { next }
  { s = $0; gsub(/[\200-\277]/, "", s); if (length(s) > 80) print FILENAME ":" FNR ":" $0 }
' "${files[@]}" 2>"$err") || tooling
if [ -n "$too_wide" ]; then
  echo "lines over 80 columns in hard-wrapped files (see docs/contributing/coding-standards.md):"
  echo "$too_wide"
  found=1
fi
exit "$found"
