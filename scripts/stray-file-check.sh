#!/usr/bin/env bash
# A tracked path outside the top-level entries this repo owns. PR #197 committed
# `null.x` at the root through a `git add -A` and it survived two review rounds,
# because nothing looked for one; a stray file is invisible in a diff nobody
# scrolls to the end of. The allowlist, whole: the top-level directories `.claude/`,
# `.github/`, `.out-of-scope/`, `docs/`, `scripts/`, `skills/` and `tests/`, and
# the root files `CLAUDE.md`, `CONTEXT.md` and `skills-lock.json`, which is
# `dirs` and `files` below. A new top-level entry is a decision rather than a
# side effect, so it is added there in the same commit that tracks it. The
# `stray-files` gate in scripts/local-gate.sh runs this, in every lane.
#
#   scripts/stray-file-check.sh [<root>]
#
# stdout: one line per tracked path outside the allowlist, nothing when clean
# exit: 0 clean · 1 a stray path · 2 tooling
set -uo pipefail
root=${1:-.}
[ -d "$root" ] || { printf 'not a directory: %s\n' "$root" >&2; exit 2; }

dirs=" .claude .github .out-of-scope docs scripts skills tests "
files=" CLAUDE.md CONTEXT.md skills-lock.json "

# The index, not the working tree: scratch a run leaves behind is not a stray,
# and a `git ls-files` outside a checkout is tooling rather than a clean answer.
# So is one inside a checkout below its top, where `ls-files` answers with paths
# relative to that subdirectory and every one of them reads as stray.
toplevel=$(git -C "$root" rev-parse --show-toplevel) || exit 2
[ "$toplevel" = "$(cd "$root" && pwd -P)" ] \
  || { printf 'not the top of a checkout: %s\n' "$root" >&2; exit 2; }
# NUL-delimited, because `git ls-files` C-quotes a name carrying a tab or a
# newline, and a quoted path has no top-level entry to match: an owned file would
# read as stray, under a name the message misprints. A command substitution drops
# NULs, so the list goes through a file.
list=$(mktemp) || exit 2
trap 'rm -f "$list"' EXIT
git -C "$root" ls-files -z > "$list" || exit 2

rc=0
while IFS= read -r -d '' p; do
  [ -n "$p" ] || continue
  top=${p%%/*}
  if [ "$top" = "$p" ]; then
    case $files in *" $p "*) continue ;; esac
  else
    case $dirs in *" $top "*) continue ;; esac
  fi
  printf "%s: tracked outside the repo's top-level allowlist\n" "$p"
  rc=1
done < "$list"
exit $rc
