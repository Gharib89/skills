#!/usr/bin/env bash
# A tracked path outside the trees this repo owns. PR #197 committed `null.x` at
# the root through a `git add -A` and it survived two review rounds, because
# nothing looked for one; a stray file is invisible in a diff nobody scrolls to
# the end of. The allowlist, whole: the top-level directories `.claude/`,
# `.github/`, `.out-of-scope/`, `docs/`, `scripts/`, `skills/` and `tests/`, and
# the root files `CLAUDE.md`, `CONTEXT.md` and `skills-lock.json`. A new
# top-level entry is a decision rather than a side effect, so it is added here in
# the same commit that tracks it. The `stray-files` gate in
# scripts/local-gate.sh runs this, in every lane.
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
tracked=$(git -C "$root" ls-files) || exit 2

rc=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  top=${p%%/*}
  if [ "$top" = "$p" ]; then
    case $files in *" $p "*) continue ;; esac
  else
    case $dirs in *" $top "*) continue ;; esac
  fi
  printf "%s: tracked outside the repo's top-level allowlist\n" "$p"
  rc=1
done <<< "$tracked"
exit $rc
