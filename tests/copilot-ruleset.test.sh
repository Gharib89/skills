#!/usr/bin/env bash
# host_copilot_review_on_push: the ruleset walk preflight refuses a contradicting
# Copilot block on. `api` is a stub here, so the walk is asserted without a host:
# what it does with two rulesets, with none carrying the rule, with a read that
# fails, and with a ruleset carrying the rule twice.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
# The adapter reads these at source time; no case here reaches a host.
SHIP_OWNER=owner SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh

# The stub answers by URL, so a case sets only the rulesets it wants to exist.
# `$LIST` is the active ids, space separated; `$RULES` is one `<id><TAB><value>`
# line per copilot_code_review rule, so a ruleset carrying the rule twice is two
# lines with the same id and one carrying it not at all has none.
api() { # <path> [--jq <filter>]
  local id
  case $1 in
    */rulesets)   for id in $LIST; do printf '%s\n' "$id"; done ;;
    */rulesets/*) awk -F'\t' -v id="${1##*/}" '$1 == id { print $2 }' <<<"$RULES" ;;
    *) return 1 ;;
  esac
}

LIST="10" RULES="10	true"
check "one active ruleset with review_on_push: true" \
  'true' "$(host_copilot_review_on_push)"

LIST="10" RULES="10	false"
check "one active ruleset with review_on_push: false" \
  'false' "$(host_copilot_review_on_push)"

# The list holds every active ruleset, and most of them govern something else.
LIST="10 11" RULES="11	true"
check "a ruleset carrying no copilot_code_review rule is walked past" \
  'true' "$(host_copilot_review_on_push)"

LIST="10 11" RULES=""
check "no copilot_code_review rule anywhere reads as false, nothing drawing a round from a push" \
  'false' "$(host_copilot_review_on_push)"

LIST="" RULES=""
check "no active ruleset at all reads as false" \
  'false' "$(host_copilot_review_on_push)"

# A ruleset carrying the rule twice is pathological, but a two-line value matches
# neither `case` arm, so without the trim it would read as "no rule here" and the
# walk would answer false for a repo that re-reviews every push.
LIST="10" RULES="10	true
10	true"
check "a ruleset answering on two lines takes the first, not neither" \
  'true' "$(host_copilot_review_on_push)"

# A check that could not run must not come back as an answer: preflight reads the
# exit status to decide between refusing and warning.
api() { return 1; }
out=$(host_copilot_review_on_push); rc=$?
check_rc "a failed rulesets read is non-zero" 1 "$rc"
check "a failed rulesets read prints nothing to mistake for an answer" '' "$out"

api() { case $1 in */rulesets) printf '10\n' ;; *) return 1 ;; esac; }
out=$(host_copilot_review_on_push); rc=$?
check_rc "a failed per-id read is non-zero too" 1 "$rc"
check "a failed per-id read prints nothing either" '' "$out"

finish
