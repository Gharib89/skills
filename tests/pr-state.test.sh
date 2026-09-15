#!/usr/bin/env bash
# ship_pr_state_reason: the refusal `merge` reads off the PR's own state before
# it squashes. A pure string-in, string-out decision; the live path, a closed PR
# driven at `merge`, is the `github-mechanics` verification's job.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

check "an open PR admits the merge"    "" "$(ship_pr_state_reason open)"
check "a merged PR admits the merge"   "" "$(ship_pr_state_reason merged)"

check "a closed PR refuses, naming the state" \
  "pr-closed: closed" "$(ship_pr_state_reason closed)"

# Both adapters normalise to the three states, so anything else is a state
# nobody wrote this function for. A check that could not ask its question must
# not answer "open", so the refusal stands, the rule ship_stale_base_reason
# follows.
check "a state nobody normalised refuses" \
  "pr-closed: abandoned" "$(ship_pr_state_reason abandoned)"

check "a state that could not be read refuses" \
  "pr-closed: state unreadable" "$(ship_pr_state_reason '')"

finish
