#!/usr/bin/env bash
# `host_pr_review_queued`: the GitHub adapter's answer to whether a login has a
# round queued since an instant, over the PR's review_requested events and the
# logins pending on it now. `_gh_queued_select`, the selection, is driven as a
# pure jq transformation; the function itself runs with the adapter's `api`
# redefined to answer fixtures, so the Copilot alias it passes and the reads it
# fails on are held too. No call in this file reaches a host. The shapes are
# those observed since #266: a quota-out Copilot left no event and no pending
# entry (#284).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh
SHIP_OWNER=o SHIP_REPO=r
source skills/ship/scripts/host/github.sh

since=2026-09-24T17:51:12Z
bot='copilot-pull-request-reviewer[bot]'

# queued <login> <alias> <events-json> <pending-json>: the adapter's call, in isolation.
queued() {
  jq -n --argjson e "$3" --argjson p "$4" --arg l "$1" --arg alias "$2" --arg s "$since" "$_gh_queued_select"
}
ev() { jq -cn --arg l "$1" --arg at "$2" '{login: $l, created_at: $at}'; }

check "no event and nothing pending is not queued" false "$(queued "$bot" Copilot '[]' '[]')"

check "the ruleset's event seconds after the PR opened is queued, under the alias" true \
  "$(queued "$bot" Copilot "[$(ev Copilot 2026-09-24T17:51:14Z)]" '[]')"

check "an event at --since itself is queued" true \
  "$(queued "$bot" Copilot "[$(ev Copilot "$since")]" '[]')"

check "an event before --since answered an earlier request" false \
  "$(queued "$bot" Copilot "[$(ev Copilot 2026-09-24T17:40:00Z)]" '[]')"

check "a pending entry is queued whatever the timeline says" true \
  "$(queued "$bot" Copilot '[]' '["Copilot"]')"

check "another reviewer's event is not this one's" false \
  "$(queued "$bot" Copilot "[$(ev someone-else 2026-09-24T17:52:00Z)]" '["someone-else"]')"

check "a login is matched less its [bot] suffix, with no alias" true \
  "$(queued 'github-actions[bot]' '' "[$(ev github-actions 2026-09-24T17:52:00Z)]" '[]')"

check "and in any case" true "$(queued "$bot" Copilot '[]' '["copilot"]')"

# The function over a stubbed `api`: each read answers what its own `--jq`
# would have printed, the timeline one event per line.
TIMELINE='' PENDING='[]' FAIL=''
api() {
  case $1 in
    */timeline) [ "$FAIL" != timeline ] || return 1; printf '%s' "$TIMELINE" ;;
    */pulls/7)  [ "$FAIL" != pulls ] || return 1; printf '%s\n' "$PENDING" ;;
    *) echo "unexpected api call: $*" >&2; return 1 ;;
  esac
}
TIMELINE=$(ev Copilot 2026-09-24T17:51:14Z)
check "the function passes Copilot's alias to the selection" true \
  "$(host_pr_review_queued 7 "$bot" "$since")"
check "and none to another login" false "$(host_pr_review_queued 7 'claude[bot]' "$since")"
TIMELINE='' PENDING='["Copilot"]'
check "a pending entry reaches the selection" true "$(host_pr_review_queued 7 "$bot" "$since")"
TIMELINE='' PENDING='[]'
check "nothing on either read is false" false "$(host_pr_review_queued 7 "$bot" "$since")"
for FAIL in timeline pulls; do
  out=$(host_pr_review_queued 7 "$bot" "$since"); rc=$?
  check "a failed $FAIL read is non-zero" 1 "$rc"
  check "and answers nothing" '' "$out"
done

finish
