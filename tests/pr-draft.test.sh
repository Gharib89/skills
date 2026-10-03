#!/usr/bin/env bash
# `host_pr_get` carries the PR's draft flag on both hosts (#458): phase 6's
# Done-when gates on "an open, non-draft PR", and without the field the run
# confirmed it with a direct host read no mechanic performs. Each adapter's
# own projection runs over a raw fixture; `api` and `az` are stubbed, so no
# case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

gh_pull() { # <draft>
  jq -n --argjson d "$1" '{number: 7, html_url: "u", title: "t", body: "", draft: $d,
    head: {sha: "s", ref: "h"}, base: {ref: "main"}, merged: false, state: "open",
    mergeable: true, mergeable_state: "clean"}'
}
ado_pull() { # <isDraft>
  jq -n --argjson d "$1" '{pullRequestId: 7, title: "t", description: "", isDraft: $d,
    lastMergeSourceCommit: {commitId: "s"}, sourceRefName: "refs/heads/h",
    targetRefName: "refs/heads/main", status: "active", mergeStatus: "succeeded"}'
}

(
  SHIP_OWNER=owner SHIP_REPO=repo
  source skills/ship/scripts/host/github.sh
  api() { jq "${@: -1}" <<<"$pull"; } # the call's own --jq over the fixture
  pull=$(gh_pull true);  check "GitHub: a draft PR reads draft true" true "$(host_pr_get 7 | jq .draft)"
  pull=$(gh_pull false); check "GitHub: a ready PR reads draft false" false "$(host_pr_get 7 | jq .draft)"
  finish
); gh=$?

(
  SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
  source skills/ship/scripts/host/ado.sh
  az() { printf '%s\n' "$pull"; }
  pull=$(ado_pull true);  check "Azure DevOps: a draft PR reads draft true" true "$(host_pr_get 7 | jq .draft)"
  pull=$(ado_pull false); check "Azure DevOps: a ready PR reads draft false" false "$(host_pr_get 7 | jq .draft)"
  finish
); ado=$?
exit $(( gh | ado ))
