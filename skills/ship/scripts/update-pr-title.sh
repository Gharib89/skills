#!/usr/bin/env bash
# Set the PR title on the host, then read it back and report it. `merge` passes
# the title verbatim as the squash subject, so a mistitled PR is retitled here,
# never by hand.
#
#   update-pr-title <pr> --title "<subject>"
#
# stdout: {pr, title, changed}
# exit: 0 · 1 update failed · 2 usage
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
pr=${1:?usage: update-pr-title <pr> --title "<subject>"}; shift
title=""
while [ $# -gt 0 ]; do
  case $1 in
    --title) title=${2:?}; shift 2 ;;
    *) ship_tooling "unknown flag: $1" ;;
  esac
done
[ -n "$title" ] || ship_tooling 'usage: update-pr-title <pr> --title "<subject>"'
ship_load_host

before=$(host_pr_get "$pr" | jq -r .title) || ship_tooling "cannot read PR $pr"
if [ "$before" = "$title" ]; then
  jq -n --argjson pr "$pr" --arg t "$title" '{pr: $pr, title: $t, changed: false}'
  exit 0
fi
host_pr_set_title "$pr" "$title" || ship_fail "PR title update failed"
# The write is proven by the read-back, never by the call's exit code.
after=$(host_pr_get "$pr" | jq -r .title) || ship_tooling "cannot read PR $pr back"
[ "$after" = "$title" ] || ship_fail "PR title read back as: $after"
jq -n --argjson pr "$pr" --arg t "$title" '{pr: $pr, title: $t, changed: true}'
