#!/usr/bin/env bash
# host_pr_merge hands the gated head to the host, which refuses the merge when
# the PR's head has moved (#635). GitHub takes it as `sha` on the REST merge.
# On Azure DevOps `az repos pr update` fills lastMergeSourceCommit from its own
# read at call time and has no flag for it, and `az devops invoke` resolves
# git/pullRequests to the project-level read route, so the completion is an
# `az rest` PATCH on the repository's PR route, carrying the head and the
# completion options the az call set, on either credential. Each adapter's
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

ado() { # [pat]: runs the ADO adapter's merge with az stubbed, keeping its argv and body
  rm -f "$work/az" "$work/body"
  (
    SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT="my proj" SHIP_REPO=repo
    if [ -n "${1:-}" ]; then export AZURE_DEVOPS_EXT_PAT=$1; else unset AZURE_DEVOPS_EXT_PAT; fi
    source skills/ship/scripts/_lib.sh
    source skills/ship/scripts/host/ado.sh
    az() {
      printf '%s\n' "$@" > "$work/az"
      while [ $# -gt 0 ]; do [ "$1" = --body ] && cp "${2#@}" "$work/body"; shift; done
      printf '{}\n'
    }
    host_pr_merge 7 "fix: x (#7)" abc123
  )
}
arg() { grep -A1 -x -- "$1" "$work/az" | tail -1; }
has() { grep -qx -- "$1" "$work/az" && echo true; }

ado
check "ADO completes the PR with a PATCH on the repository's PR route" \
  "patch https://dev.azure.com/org/my%20proj/_apis/git/repositories/repo/pullRequests/7?api-version=7.1" \
  "$(arg --method) $(arg --url)"
check "the body carries the gated head and the completion options" \
  '{"status":"completed","lastMergeSourceCommit":{"commitId":"abc123"},"completionOptions":{"mergeStrategy":"squash","deleteSourceBranch":true,"transitionWorkItems":true,"mergeCommitMessage":"fix: x (#7)"}}' \
  "$(jq -c '{status, lastMergeSourceCommit, completionOptions: (.completionOptions | {mergeStrategy, deleteSourceBranch, transitionWorkItems, mergeCommitMessage})}' "$work/body" 2>/dev/null)"
check "an az login session takes an Azure DevOps token" 499b84ac-1321-427f-aa17-267ca6975798 "$(arg --resource)"

ado s3cret
check "a PAT session sends the PAT as Basic auth instead" "true true" \
  "$(has --skip-authorization-header) $(has "Authorization=Basic $(printf ':s3cret' | base64 -w0)")"
check "and asks az for no token" "" "$(has --resource)"

finish
