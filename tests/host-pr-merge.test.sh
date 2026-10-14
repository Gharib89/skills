#!/usr/bin/env bash
# host_pr_merge hands the gated head to the host, which refuses the merge when
# the PR's head has moved (#635). GitHub takes it as `sha` on the REST merge.
# On Azure DevOps `az repos pr update` fills lastMergeSourceCommit from its own
# read at call time and has no flag for it, so the completion is a REST PATCH
# carrying the head and the completion options the az call set. Each adapter's
# transport is stubbed, so no case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

(
  SHIP_OWNER=owner SHIP_REPO=repo
  source skills/ship/scripts/_lib.sh
  source skills/ship/scripts/host/github.sh
  api() { printf '%s\n' "$@" > "$work/gh"; }
  host_pr_merge 7 "fix: x (#7)" abc123
)
check "GitHub squash-merges with the subject and the gated head as sha" \
  "PUT
repos/owner/repo/pulls/7/merge
merge_method=squash
commit_title=fix: x (#7)
sha=abc123" "$(grep -v '^-' "$work/gh")"

(
  SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
  source skills/ship/scripts/_lib.sh
  source skills/ship/scripts/host/ado.sh
  az() { # keeps the argv and the request body
    printf '%s\n' "$@" > "$work/az"
    while [ $# -gt 0 ]; do [ "$1" = --in-file ] && cp "$2" "$work/body"; shift; done
    printf '{}\n'
  }
  host_pr_merge 7 "fix: x (#7)" abc123
)
arg() { grep -A1 -x -- "$1" "$work/az" | tail -1; }
check "ADO completes the PR through a PATCH on pullRequests" "PATCH git pullRequests" \
  "$(arg --http-method) $(arg --area) $(arg --resource)"
check "the route names the PR" true "$(grep -qx pullRequestId=7 "$work/az" && echo true)"
check "the body carries the gated head and the completion options" \
  '{"status":"completed","lastMergeSourceCommit":{"commitId":"abc123"},"completionOptions":{"mergeStrategy":"squash","deleteSourceBranch":true,"transitionWorkItems":true,"mergeCommitMessage":"fix: x (#7)"}}' \
  "$(jq -cS . "$work/body" 2>/dev/null | jq -c '{status, lastMergeSourceCommit, completionOptions: (.completionOptions | {mergeStrategy, deleteSourceBranch, transitionWorkItems, mergeCommitMessage})}')"

finish
