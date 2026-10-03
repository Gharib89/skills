#!/usr/bin/env bash
# Removing an Azure DevOps tag (#453): a System.Tags write through
# `az boards work-item update --fields` merges into the tags already there, so
# the lab kept `ready-for-agent` after a hand-back wrote the set without it.
# Only a json-patch `replace` drops a tag, and `remove` clears the last one.
# `az` and `host_issue_get` are stubbed, so no case here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/ado.sh

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host_issue_get() { jq -n --argjson l "$(cat "$work/labels")" '{number: 7, labels: $l}'; }
az() { # logs each subcommand, and records the json-patch body `az rest` sends
  printf '%s\n' "$1" >> "$work/calls"
  while [ $# -gt 0 ]; do [ "$1" = --body ] && printf '%s' "$2" > "$work/patch"; shift; done
}
labels() { printf '%s' "$1" > "$work/labels"; rm -f "$work/patch" "$work/calls"; }

labels '["needs-triage","ready-for-agent","ready-for-human"]'
host_issue_remove_label 7 ready-for-agent
check "a tag beside others is replaced away, not merged back" \
  '[{"op":"replace","path":"/fields/System.Tags","value":"needs-triage; ready-for-human"}]' \
  "$(jq -c . "$work/patch" 2>/dev/null)"
check "in one az rest call, no merging update" rest "$(cat "$work/calls" 2>/dev/null)"

labels '["ready-for-agent"]'
host_issue_remove_label 7 ready-for-agent
check "the last tag is removed" '[{"op":"remove","path":"/fields/System.Tags"}]' "$(jq -c . "$work/patch" 2>/dev/null)"

# A host blip on the write is retried once, as every other az call is.
labels '["needs-triage","ready-for-agent"]'
az() { printf '%s\n' "$1" >> "$work/calls"; [ "$(wc -l < "$work/calls")" -gt 1 ]; }
sleep() { :; }
host_issue_remove_label 7 ready-for-agent; rc=$?
check_rc "a failed write that succeeds on retry is a success" 0 "$rc"
check "after two attempts" "rest rest" "$(paste -sd' ' "$work/calls")"

labels '["needs-triage"]'
host_issue_remove_label 7 ready-for-agent; rc=$?
check_rc "an absent tag is a no-op success" 0 "$rc"
check "with no write" "" "$(cat "$work/patch" "$work/calls" 2>/dev/null)"

finish
