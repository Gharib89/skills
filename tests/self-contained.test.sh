#!/usr/bin/env bash
# scripts/self-contained-check.sh: a skill's prose points only at material that
# installs with it. Each case builds a checkout under a fresh root and tracks one
# skill file in it, because the subject is what a derived copy carries, which is
# the tracked tree under `skills/<name>/`.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <case> <path> <line>: a checkout tracking one file holding <line>; prints its path.
repo() {
  local d="$fixture/$1"
  rm -rf "$d"; mkdir -p "$d/$(dirname "$2")" || return 1
  git -C "$d" init -q || return 1
  printf '%s\n' "$3" > "$d/$2" || return 1
  git -C "$d" add -Af || return 1
  printf '%s' "$d"
}
rc_of()  { bash scripts/self-contained-check.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { bash scripts/self-contained-check.sh "$1" 2>/dev/null; }

# The real tree, so a leak committed here fails a case rather than leaving every
# synthetic fixture green.
check_rc "the current tree is self-contained" 0 "$(rc_of .)"

d=$(repo glossary skills/a/SKILL.md 'Vocabulary: [CONTEXT.md](https://github.com/Gharib89/skills/blob/main/CONTEXT.md).')
check_rc "a URL to a source-repo file fails" 1 "$(rc_of "$d")"
check "the message names the file, the line and the reason" \
  "skills/a/SKILL.md:1: links source-repo material by URL" "$(out_of "$d")"

d=$(repo issue-link skills/a/SKILL.md 'is to read the profile ([#367](https://github.com/Gharib89/skills/issues/367)).')
check_rc "an issue link fails" 1 "$(rc_of "$d")"

d=$(repo pr-link skills/a/reviewers/x.md 'probed on a runner, [run on #174](https://github.com/Gharib89/skills/pull/174)')
check_rc "a PR link fails" 1 "$(rc_of "$d")"

d=$(repo destination skills/a/reference/detection.md 'file an issue on [Gharib89/skills](https://github.com/Gharib89/skills/issues) asking for its entry.')
check_rc "the issue tracker as a destination passes" 0 "$(rc_of "$d")"

d=$(repo pr-number skills/a/SKILL.md 'PR #212 is the case.')
check_rc "a bare PR number fails" 1 "$(rc_of "$d")"
check "the message names the reason" \
  "skills/a/SKILL.md:1: cites an issue or PR number" "$(out_of "$d")"

# A consumer's own tracker syntax, quoted as an example, is not a citation.
d=$(repo number-example skills/a/reference/merge-gate.md 'An entry naming an issue by number (`#<n>`, such as `map issue #1`) is kept.')
check_rc "a number inside a code span passes" 0 "$(rc_of "$d")"

d=$(repo root-link skills/a/SKILL.md 'See [CONTEXT.md](../../CONTEXT.md).')
check_rc "a relative link above the skill fails" 1 "$(rc_of "$d")"
check "the message names the target" \
  "skills/a/SKILL.md:1: links outside skills/a/: ../../CONTEXT.md" "$(out_of "$d")"

d=$(repo sibling-link skills/a/SKILL.md 'See [ship](../ship/SKILL.md#process).')
check_rc "a relative link into a sibling skill fails" 1 "$(rc_of "$d")"

d=$(repo own-link skills/a/reference/cloud.md 'From [templates/x.sh](../templates/x.sh) and [the ladder](check-ladder.md#rungs).')
check_rc "a relative link inside the skill passes" 0 "$(rc_of "$d")"

d=$(repo changelog skills/a/CHANGELOG.md '- **a**: fix ([#378](https://github.com/Gharib89/skills/pull/378))')
check_rc "a changelog carries provenance and passes" 0 "$(rc_of "$d")"

d=$(repo outside docs/agents/ship.md 'See [ADR 0004](https://github.com/Gharib89/skills/blob/main/docs/adr/0004.md) and PR #212.')
check_rc "a file outside skills/ passes" 0 "$(rc_of "$d")"

d=$(repo untracked skills/a/SKILL.md 'Clean.'); printf 'PR #1\n' > "$d/skills/a/notes.md"
check_rc "an untracked file passes" 0 "$(rc_of "$d")"

check_rc "a root that is not a checkout is tooling" 2 "$(rc_of "$fixture")"
check_rc "a root that does not exist is tooling" 2 "$(rc_of "$fixture/absent")"

finish
