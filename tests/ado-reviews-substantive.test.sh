#!/usr/bin/env bash
# host_pr_reviews() on Azure DevOps sends no `substantive` (#270): poll-pr grades
# every row itself (`SHIP_SUBSTANTIVE`, #268), and the host contract lists no such
# field, so a key the adapter set would contradict it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
# The adapter reads these at source time; `azx` and `invoke` are stubbed below,
# so no case here reaches a host.
SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/ado.sh

# One vote and one thread on the latest iteration: a row of each kind the
# adapter emits, in both `on_head` and `all`.
azx() { echo '[{"uniqueName": "voter@example.com", "vote": 10}]'; }
invoke() {
  case $3 in
    pullRequestIterations) echo '{"value": [{"id": 2, "createdDate": "2026-09-24T09:00:00Z"}]}' ;;
    pullRequestThreads) echo '{"value": [{"id": 41, "publishedDate": "2026-09-24T09:05:00.000Z",
      "pullRequestThreadContext": {"iterationContext": {"secondComparingIteration": 2}},
      "comments": [{"content": "a finding", "author": {"uniqueName": "reviewer@example.com"}}]}]}' ;;
  esac
}

out=$(host_pr_reviews 7 abc123)
check "both row kinds reach on_head" "approved comment" "$(jq -r '[.on_head[].state] | join(" ")' <<<"$out")"
check "no row carries substantive" false "$(jq '[.on_head[], .all[]] | any(has("substantive"))' <<<"$out")"

finish
