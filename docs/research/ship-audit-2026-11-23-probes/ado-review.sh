#!/usr/bin/env bash
set -uo pipefail
src=$PWD/skills/ship/scripts
source "$src/_lib.sh"
source "$src/host/ado.d/prs.sh"
ORG=()
SHIP_PROJECT=project; SHIP_REPO=repo
azx() { printf '[]\n'; }
invoke() {
  case $3 in
    pullRequestIterations)
      [ "${ITERATION_CASE:-works}" = works ] || return 1
      printf '{"value":[{"id":2,"createdDate":"2026-11-23T13:00:00Z"}]}\n' ;;
    pullRequestThreads)
      printf '{"value":[{"id":1,"publishedDate":"2026-11-23T12:00:00Z","comments":[{"author":{"uniqueName":"review@example.com"},"content":"An old review","commentType":"text"}]}]}\n' ;;
    *) return 99 ;;
  esac
}
echo 'Iteration read succeeds:'
host_pr_reviews 7 bbbb | jq -c .on_head
echo 'Iteration read fails:'
ITERATION_CASE=failure host_pr_reviews 7 bbbb | jq -c .on_head
