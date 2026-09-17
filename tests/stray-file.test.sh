#!/usr/bin/env bash
# scripts/stray-file-check.sh: the tracked paths this repo owns. Most cases
# build a checkout under a fresh root and track paths in it, because the
# subject is the index rather than the working tree: a stray nobody committed is
# not one. The fixtures track files without committing, which `git ls-files`
# reads and which needs no identity configured.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <case> <path>...: a checkout tracking each path; prints its path.
repo() {
  local d="$fixture/$1" p; shift
  rm -rf "$d"; mkdir -p "$d" || return 1
  git -C "$d" init -q || return 1
  for p in "$@"; do mkdir -p "$d/$(dirname "$p")" && : > "$d/$p" || return 1; done
  git -C "$d" add -A || return 1
  printf '%s' "$d"
}
rc_of()  { bash scripts/stray-file-check.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { bash scripts/stray-file-check.sh "$1" 2>/dev/null; }

# The real tree, so a stray committed here fails a case rather than leaving
# every synthetic fixture green.
check_rc "the current tree tracks nothing stray" 0 "$(rc_of .)"

d=$(repo owned skills/ship/SKILL.md .claude/skills/ship/SKILL.md docs/agents/ship.md \
  scripts/local-gate.sh tests/run.sh .github/workflows/claude-review.yml \
  .out-of-scope/note.md CLAUDE.md CONTEXT.md skills-lock.json)
check_rc "a checkout of owned paths passes" 0 "$(rc_of "$d")"

d=$(repo stray-root skills/ship/SKILL.md null.x)
check_rc "a stray root file fails" 1 "$(rc_of "$d")"
check "the message names the path" \
  "null.x: tracked outside the repo's top-level allowlist" "$(out_of "$d")"

d=$(repo stray-dir skills/ship/SKILL.md src/main.sh)
check_rc "a stray top-level directory fails" 1 "$(rc_of "$d")"
check "the message names the path, not the directory" \
  "src/main.sh: tracked outside the repo's top-level allowlist" "$(out_of "$d")"

# Untracked is not tracked: scratch a run leaves in the tree is not a finding,
# which is what keeps this gate from firing on a worktree mid-run.
d=$(repo untracked skills/ship/SKILL.md); : > "$d/null.x"
check_rc "an untracked stray passes" 0 "$(rc_of "$d")"

# The tooling paths: a root outside any checkout, a root that is not there, and a
# root inside a checkout that is not its top. `git ls-files` answers that last
# one with paths relative to the subdirectory, which reads as every tracked file
# being stray, so the check refuses it rather than answering about a tree it was
# not given.
check_rc "a root that is not a checkout is tooling" 2 "$(rc_of "$fixture")"
check_rc "a root that does not exist is tooling" 2 "$(rc_of "$fixture/absent")"

d=$(repo subdir skills/ship/SKILL.md docs/agents/ship.md)
check_rc "a subdirectory of a checkout is tooling" 2 "$(rc_of "$d/docs")"

finish
