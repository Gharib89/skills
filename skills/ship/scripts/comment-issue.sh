#!/usr/bin/env bash
# Post a comment on an existing issue (an adjacent find's later evidence, where
# the issue is what a triager reads). On Azure DevOps this is a discussion entry
# on the work item.
#
#   comment-issue <issue> --body-file <path>
#
# stdout: {issue, posted: true}, or on failure {issue, posted: false, error, status}
#         with the HTTP status of the last attempt, null where the host reported none
# exit: 0 · 1 post failed · 2 usage
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: comment-issue <issue> --body-file <path>'
ship_help "$usage" "$@"
[ -n "${1:-}" ] || ship_tooling "$usage"
n=$1; shift
case $n in -*) ship_tooling "$usage" ;; esac
[ "${1:-}" = --body-file ] && [ -f "${2:-}" ] && [ $# -eq 2 ] || ship_tooling "$usage"
ship_load_host
if ! answer=$(host_issue_comment "$n" "$(cat "$2")"); then
  # ship_fail_host exits, so it runs in the subshell and its verdict is extended.
  verdict=$(ship_fail_host "comment on issue #$n failed" "$answer")
  jq --argjson n "$n" '{issue: $n, posted: false} + .' <<<"$verdict"
  exit 1
fi
jq -n --argjson n "$n" '{issue: $n, posted: true}'
