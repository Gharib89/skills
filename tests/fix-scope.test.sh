#!/usr/bin/env bash
# scripts/check-fix-scope.sh: a `fix`-titled PR whose diff touches `skills/` or
# `docs/agents/` carries a `Fix scope:` line naming `procedure` or `domain`. The
# seam is the script's environment (PR_TITLE, PR_BODY, PR_BASE, PR_ROOT), so each
# case builds a throwaway repo, commits a base and a change on a branch, and
# drives it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <case> <path>: a repo whose `pr` branch changes that one path.
repo() {
  local r="$fixture/$1"
  mkdir -p "$r/$(dirname "$2")"
  git -C "$r" init -q -b main
  printf 'x\n' > "$r/$2"
  git -C "$r" add -A
  git -C "$r" -c user.name=t -c user.email=t@t commit -q -m base
  git -C "$r" checkout -q -b pr
  printf 'y\n' >> "$r/$2"
  git -C "$r" add -A
  git -C "$r" -c user.name=t -c user.email=t@t commit -q -m change
  printf '%s' "$r"
}
# <repo> <title> <body>: leaves the exit code in `rc` and stdout in `out`.
scope() {
  out=$(PR_ROOT=$1 PR_BASE=main PR_TITLE=$2 PR_BODY=$3 bash scripts/check-fix-scope.sh 2>/dev/null); rc=$?
}
wrap() { printf '## Why\n\nx\n\n## Special things to note\n\n- 🟢 Door: two-way.\n%s\n## Needs attention\n\nNone.\n' "$1"; }

skill=$(repo skill skills/demo/SKILL.md)
agents=$(repo agents docs/agents/ship.md)

scope "$skill" 'fix(demo): reword' "$(wrap '')"
check_rc "a fix title touching skills/ with no Fix scope line fails" 1 "$rc"
check "naming the missing line" 1 "$(printf '%s\n' "$out" | grep -c 'Fix scope:')"
scope "$skill" 'fix: reword' "$(wrap '')"
check_rc "a scopeless fix title is still a fix" 1 "$rc"
scope "$skill" 'fix(demo): reword' "$(wrap '- Fix scope: procedure, exposed by #1174.')"
check_rc "Fix scope: procedure passes" 0 "$rc"
scope "$skill" 'fix(demo): reword' "$(wrap '* Fix scope: domain, exposed by a ship run.')"
check_rc "a star marker and domain pass" 0 "$rc"
scope "$skill" 'fix(demo): reword' "$(wrap '1. Fix scope: domain, exposed by a run.')"
check_rc "a numbered marker passes" 0 "$rc"
scope "$skill" 'fix(demo): reword' "$(wrap '+ Fix scope: procedure.')"
check_rc "a plus marker passes" 0 "$rc"
scope "$skill" 'fix(demo): reword' "$(wrap 'Fix scope: procedure.')"
check_rc "a bare line with no list marker passes" 0 "$rc"
scope "$skill" 'fix(demo): reword' "$(wrap '- Fix scope: both, it is complicated.')"
check_rc "a line naming neither procedure nor domain fails" 1 "$rc"
scope "$skill" 'fix(demo): reword' "$(wrap '- Fix scope:')"
check_rc "an empty Fix scope line fails" 1 "$rc"
scope "$skill" 'fix(demo): reword' "$(wrap '<!-- Fix scope: procedure -->')"
check_rc "a line inside an HTML comment does not count" 1 "$rc"
scope "$skill" 'fix(demo): reword' "$(wrap 'See the Fix scope: procedure note.')"
check_rc "the line must start with Fix scope:" 1 "$rc"
scope "$skill" 'feat(demo): reword' "$(wrap '')"
check_rc "a feat title passes without the line" 0 "$rc"
scope "$agents" 'fix(ci): profile' "$(wrap '')"
check_rc "a fix title touching docs/agents/ with no line fails" 1 "$rc"
scope "$agents" 'fix(ci): profile' "$(wrap '- Fix scope: domain, exposed by #1242.')"
check_rc "the same diff passes with the line" 0 "$rc"

scripts=$(repo scripts scripts/check.sh)
tests=$(repo tests tests/x.test.sh)
scope "$scripts" 'fix(ci): tweak' "$(wrap '')"
check_rc "a fix title touching only scripts/ passes" 0 "$rc"
scope "$tests" 'fix(ci): tweak' "$(wrap '')"
check_rc "a fix title touching only tests/ passes" 0 "$rc"

finish
