#!/usr/bin/env bash
# host_copilot_review_on_push: the branch-rules read preflight refuses a
# contradicting Copilot block on. `api` is a stub here, so the walk is asserted
# without a host: what it does with no rule on the branch, with two rules, and
# with a read that fails at either of the two calls.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
# The adapter reads these at source time; no case here reaches a host.
SHIP_OWNER=owner SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh

# `$BRANCH` is what the repo read answers; `$RULES` is one review_on_push value
# per line, standing for the copilot_code_review rules the host resolved for that
# branch. Any other path is a call this function should not be making.
api() { # <path> [--paginate] [--jq <filter>]
  case $1 in
    # An `if`, not `&&`: a branch with no copilot rule is an empty list the host
    # answers successfully, and `&&` would hand back its own failure instead.
    repos/*/*/rules/branches/*) if [ -n "$RULES" ]; then printf '%s\n' "$RULES"; fi ;;
    repos/*/*)                  printf '%s\n' "$BRANCH" ;;
    *) return 1 ;;
  esac
}

BRANCH=main RULES="true"
check "a branch whose copilot rule re-reviews pushes" \
  'true' "$(host_copilot_review_on_push)"

BRANCH=main RULES="false"
check "a branch whose copilot rule does not" \
  'false' "$(host_copilot_review_on_push)"

# The endpoint resolves branch conditions host-side, so a ruleset scoped
# elsewhere simply does not appear here. That is the whole fix for a rule on
# `release/*` being read as governing the default branch.
BRANCH=main RULES=""
check "no copilot rule on this branch reads as false, nothing drawing a round from a push" \
  'false' "$(host_copilot_review_on_push)"

# Two rulesets can both carry the rule for one branch. Without the trim the
# two-line value matches neither arm and answers false for a repo that
# re-reviews every push, which is the contradiction this check exists to catch.
BRANCH=main RULES="true
false"
check "two rules on one branch take the first, not neither" \
  'true' "$(host_copilot_review_on_push)"

# A check that could not run must not come back as an answer: preflight reads the
# exit status to decide between refusing and warning.
api() { return 1; }
out=$(host_copilot_review_on_push); rc=$?
check_rc "a failed repo read is non-zero" 1 "$rc"
check "a failed repo read prints nothing to mistake for an answer" '' "$out"

api() { case $1 in repos/*/*/rules/branches/*) return 1 ;; *) printf 'main\n' ;; esac; }
out=$(host_copilot_review_on_push); rc=$?
check_rc "a failed branch-rules read is non-zero too" 1 "$rc"
check "a failed branch-rules read prints nothing either" '' "$out"

# An empty default branch is a repo read that answered without answering; going
# on would build the rules path out of nothing and ask about the wrong branch.
api() { case $1 in repos/*/*/rules/branches/*) printf 'true\n' ;; *) printf '\n' ;; esac; }
out=$(host_copilot_review_on_push); rc=$?
check_rc "an empty default branch is non-zero, not a read of /rules/branches/" 1 "$rc"
check "an empty default branch prints nothing" '' "$out"

finish
