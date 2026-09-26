#!/usr/bin/env bash
# host_pr_for_branch() carries the PR's head sha on both real adapters (#321):
# preflight prunes a worktree only at that sha, so an adapter dropping it stops
# every prune with no test failing over the Host fake. Each adapter runs with
# its transport (`api`, `azx`) redefined to answer a raw host fixture shaped as
# the live probes of GitHub PR 285 and lab PR 1 answered, so no call here
# reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

gh=$(
  SHIP_OWNER=o SHIP_REPO=r
  source skills/ship/scripts/host/github.sh
  # The adapter's `--jq` applied to the raw list, as `gh api --jq` would.
  api() { jq -c "$3" <<<'[{"number": 285, "state": "closed", "merged_at": "2026-09-20T10:00:00Z",
    "head": {"ref": "fix/free-round-never-queued-284", "sha": "e875c70a792089b949a7c434efbaf62c98ead9b8"}}]'; }
  host_pr_for_branch fix/free-round-never-queued-284
)
check "the GitHub adapter answers the PR's head sha" \
  '{"number":285,"state":"merged","head_sha":"e875c70a792089b949a7c434efbaf62c98ead9b8"}' "$(jq -c . <<<"$gh")"

ado=$(
  SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
  source skills/ship/scripts/host/ado.sh
  azx() { echo '[{"pullRequestId": 1, "status": "completed", "sourceRefName": "refs/heads/lab/270",
    "lastMergeSourceCommit": {"commitId": "c18afa554c0fbb09d85fe0a4ed52554cd875c45d"}}]'; }
  host_pr_for_branch lab/270
)
check "the Azure DevOps adapter answers the PR's head sha" \
  '{"number":1,"state":"merged","head_sha":"c18afa554c0fbb09d85fe0a4ed52554cd875c45d"}' "$(jq -c . <<<"$ado")"

finish
