#!/usr/bin/env bash
# The em-dash ban from docs/contributing/coding-standards.md, plus no trailing
# whitespace and a final newline on every non-empty file, over the files this
# repo authors. A derived repo's stock `trailing-whitespace` and
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

paths=('skills/*' 'docs/*' 'scripts/*' 'tests/*' '.github/*' '.release/*' CONTEXT.md CLAUDE.md)
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
exit "$found"
