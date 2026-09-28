#!/usr/bin/env bash
# A diff that moves a `metadata.version` line under `skills/`. The release run on
# main owns that number now: it reads the squash subject's Conventional-Commit
# type, writes the version and cuts the changelog, so a bump in a PR either loses
# to the release run or collides with another PR on the same line. The habit from
# the old rule is what this catches, before the PR opens rather than in review.
# `metadata.profile-schema` is exempt: it stays a hand edit, because the
# `## Schema N` entry it carries is written by the change that needs it. So is
# the one-time renumber to 0.x, `renumbered` below.
# See docs/adr/0003-version-and-changelog-cut-on-merge.md and 0005.
#
#   scripts/version-line-check.sh <base-ref> [<root>]
#
# stdout: one block per offending file, its changed version lines indented
# exit: 0 clean · 1 a moved version line · 2 tooling
#
# Adding a version line is not moving one: a new skill arrives carrying its first,
# and a file can gain a metadata block it did not have, so a removed version line
# is what a finding needs. A deleted skill is filtered out for the same reason.
# The comparison runs from the merge base
# to the working tree, so an uncommitted bump is caught alongside a committed one.
set -uo pipefail
[ $# -ge 1 ] && [ -n "$1" ] || { printf 'usage: scripts/version-line-check.sh <base-ref> [<root>]\n' >&2; exit 2; }
base=$1 root=${2:-.}
[ -d "$root" ] || { printf 'not a directory: %s\n' "$root" >&2; exit 2; }
git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 \
  || { printf 'not inside a git checkout: %s\n' "$root" >&2; exit 2; }
mb=$(git -C "$root" merge-base "$base" HEAD 2>/dev/null) \
  || { printf 'cannot resolve a merge base with %s\n' "$base" >&2; exit 2; }

# A version line: the key at the start of the line. The anchor is what excludes
# the documented `sed -n 's/^  version: //p'` idiom in ship's own SKILL.md, which
# carries the key mid-sentence.
line_re='^[+-][[:space:]]*version:'

# NUL-delimited through a file, because a command substitution drops NULs and a
# C-quoted name would not match the path the next command is handed.
list=$(mktemp) || exit 2
trap 'rm -f "$list"' EXIT
git -C "$root" diff -z --name-only --diff-filter=d "$mb" -- 'skills/*/SKILL.md' > "$list" || exit 2

# The renumber to 0.x (ADR 0005): one version line out and one in, M.m.p with
# M at least 1 to exactly 0.M.p, in the diff that flips the skill's
# `allow_zero_version` to true. The flip happens once per skill, so no later
# diff qualifies, a move back out of 1.x included.
renumbered() {
  local s=${1#skills/}; s=${s%%/*}
  local old new
  old=$(printf '%s\n' "$2" | sed -n 's/^-[[:space:]]*version:[[:space:]]*//p')
  new=$(printf '%s\n' "$2" | sed -n 's/^+[[:space:]]*version:[[:space:]]*//p')
  [[ $old =~ ^[1-9][0-9]*\.[0-9]+\.[0-9]+$ && $new == "0.${old%%.*}.${old##*.}" ]] || return 1
  git -C "$root" diff -U0 "$mb" -- ".release/$s.toml" \
    | grep -qx '+allow_zero_version = true'
}

rc=0
while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  hits=$(git -C "$root" diff -U0 "$mb" -- "$f" | grep -E "$line_re") || continue
  # A `+` alone is a line arriving with a new frontmatter block; a `-` is the one
  # that was already there and moved.
  printf '%s\n' "$hits" | grep -q '^-' || continue
  renumbered "$f" "$hits" && continue
  printf '%s: changes a metadata.version line, which the release run owns\n' "$f"
  printf '%s\n' "$hits" | sed 's/^/    /'
  rc=1
done < "$list"
exit $rc
