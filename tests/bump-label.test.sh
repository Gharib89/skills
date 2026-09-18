#!/usr/bin/env bash
# scripts/check-bump-label.sh: the bump grade a PR title implies, and the label a
# major one needs. The seam is the script's CLI: PR_TITLE, PR_BODY, PR_COMMITS and
# PR_LABELS in, an exit code and one message out, which is what the bump-guard
# workflow runs.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

# <title> <body> <labels> [<commit messages>]: the script's exit code.
rc_of() {
  PR_TITLE=$1 PR_BODY=$2 PR_LABELS=$3 PR_COMMITS=${4:-} \
    bash scripts/check-bump-label.sh >/dev/null 2>&1
  printf '%s' "$?"
}
# <title> <body> <labels>: the script's message.
out_of() {
  PR_TITLE=$1 PR_BODY=$2 PR_LABELS=$3 bash scripts/check-bump-label.sh 2>/dev/null
}

# --- the grades that need no label ------------------------------------------

check_rc "a fix title passes"   0 "$(rc_of 'fix(ship): stop the loop' '' '')"
check_rc "a feat title passes"  0 "$(rc_of 'feat(ship): add a flag' '' '')"
check_rc "a docs title passes"  0 "$(rc_of 'docs: reword the profile' '' '')"
check_rc "a scopeless title passes" 0 "$(rc_of 'chore: bump the pin' '' '')"

# Every type the `.release/*.toml` configurations read, so the guard and the
# release run admit the same set: a type one takes and the other drops is a
# release skipped or a PR refused for no reason.
for t in build chore ci docs feat fix perf refactor revert style test; do
  check_rc "the type $t passes" 0 "$(rc_of "$t(ship): a change" '' '')"
done

# And the same set on the other side, read out of the configurations rather than
# repeated here: `allowed_tags` is what the parser's type regex is built from, so
# a type this guard admits and that list omits parses as nothing and skips the
# release silently, which is the failure the guard exists to refuse.
guard_types=$(sed -n "s/^types='\(.*\)'$/\1/p" scripts/check-bump-label.sh | tr '|' '\n' | sort | tr '\n' ' ')
for c in .release/*.toml; do
  cfg_types=$(sed -n 's/^allowed_tags = \[\(.*\)\]$/\1/p' "$c" \
    | tr -d '" ' | tr ',' '\n' | sort | tr '\n' ' ')
  check "$c admits the types the guard does" "$guard_types" "$cfg_types"
done

# --- the major grade ---------------------------------------------------------

check_rc "a bang title without the label fails" \
  1 "$(rc_of 'feat(ship)!: rename a JSON key' '' '')"
check_rc "a bang title with the label passes" \
  0 "$(rc_of 'feat(ship)!: rename a JSON key' '' 'major')"
check_rc "a bang title with a scopeless type fails" \
  1 "$(rc_of 'refactor!: drop the mechanic' '' '')"
check_rc "a BREAKING CHANGE footer without the label fails" \
  1 "$(rc_of 'fix(ship): drop a stop reason' 'Body text.

BREAKING CHANGE: the stop reason is gone.' '')"
check_rc "the hyphen spelling of the footer fails too" \
  1 "$(rc_of 'fix(ship): drop a stop reason' 'BREAKING-CHANGE: gone.' '')"
check_rc "a footer with the label passes" \
  0 "$(rc_of 'fix(ship): drop a stop reason' 'BREAKING CHANGE: gone.' 'major')"

# This repository squashes with `COMMIT_MESSAGES`, so a footer in a branch commit
# is the one the release run grades and the description is the one that does not
# travel. Both are read, so neither reaches the release run unseen.
check_rc "a footer in a commit message without the label fails" \
  1 "$(rc_of 'fix(ship): drop a stop reason' '' '' 'fix(ship): drop a stop reason

BREAKING CHANGE: the stop reason is gone.')"
check_rc "a footer in a commit message with the label passes" \
  0 "$(rc_of 'fix(ship): drop a stop reason' '' 'major' 'BREAKING CHANGE: gone.')"
check_rc "commit messages with no footer pass" \
  0 "$(rc_of 'fix(ship): drop a stop reason' '' '' 'fix(ship): drop a stop reason

Refs #1.')"

# --- the label list ----------------------------------------------------------

check_rc "the label is found among others, comma separated" \
  0 "$(rc_of 'feat!: x' '' 'enhancement,major,L')"
check_rc "the label is found among others, newline separated" \
  0 "$(rc_of 'feat!: x' '' 'enhancement
major')"
check_rc "the label is matched case-insensitively" \
  0 "$(rc_of 'feat!: x' '' 'Major')"
check_rc "a label that merely contains it is not the label" \
  1 "$(rc_of 'feat!: x' '' 'majority')"

# --- what is not a Conventional Commit ---------------------------------------

check_rc "a title with no type fails"        1 "$(rc_of 'update the profile' '' '')"
# A type the release run does not read grades nothing, so the release is skipped
# silently rather than mis-graded. A typo is the common way in.
check_rc "a type the release run does not read fails" 1 "$(rc_of 'wip(ship): a flag' '' '')"
check_rc "a typo of a real type fails"       1 "$(rc_of 'fx(ship): the loop' '' '')"
check_rc "a type that merely starts with one fails" 1 "$(rc_of 'features: a flag' '' '')"
check_rc "a title with no description fails" 1 "$(rc_of 'fix(ship):' '' '')"
check_rc "a title with an uppercase type fails" 1 "$(rc_of 'Fix: the loop' '' '')"
check_rc "an empty title fails"              1 "$(rc_of '' '' '')"

# --- adversarial inputs, per the coding standards ----------------------------

# A colon in the description is not a second delimiter: the type is what precedes
# the FIRST one, and the rest is prose.
check_rc "a colon inside the description passes" \
  0 "$(rc_of 'docs: name the field: Reads:' '' '')"
# A bang inside the scope is not the breaking marker; the marker sits after the
# closing paren. A reviewer reading the regex left to right gets this wrong.
check_rc "a bang inside the scope is not the breaking marker" \
  0 "$(rc_of 'feat(ship!): add a flag' '' '')"
# The footer is line-anchored: a mention of the words mid-sentence is prose.
check_rc "BREAKING CHANGE mid-line in the body is prose" \
  0 "$(rc_of 'fix: x' 'This is not a BREAKING CHANGE: it restores documented behavior.' '')"
# Leading and trailing whitespace on the title is the host's, not the author's.
check_rc "a padded title is read whole" 0 "$(rc_of '  fix: the loop  ' '' '')"

# --- the messages ------------------------------------------------------------

check "the passing message names the grade" \
  "bump-guard: no major bump implied, no bump label required." \
  "$(out_of 'fix: x' '' '')"
check "the refusal names the label to add" \
  "bump-guard: this PR is a breaking change (a '!' in the title or a 'BREAKING CHANGE:' footer in the description or in a commit message), which bumps the major version. A major bump must be opted in by a maintainer: add the 'major' label to confirm, or remove the breaking change (drop the '!' / the footer)." \
  "$(out_of 'feat!: x' '' '')"
check "the invalid-title refusal names the title and the types" \
  "bump-guard: title 'update the profile' is not a Conventional Commit of a type the release run reads (build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test). PR titles must be, e.g. 'fix: ...' or 'feat(ship): ...', because the squash subject drives the release version bump." \
  "$(out_of 'update the profile' '' '')"

finish
