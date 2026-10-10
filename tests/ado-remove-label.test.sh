#!/usr/bin/env bash
# Removing an Azure DevOps tag (#453, #540): a System.Tags write through
# `az boards work-item update --fields` merges into the tags already there, so
# the lab kept `ready-for-agent` after a hand-back wrote the set without it.
# Only a json-patch `replace` drops a tag, and `remove` clears the last one. The
# patch rides in a `wit/$batch` request through `az devops invoke`, which holds
# either credential, where `az rest` needed an `az login` a PAT-only session
# lacks. `az` and `host_issue_get` are stubbed, so no case here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/ado.sh

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host_issue_get() { jq -n --argjson l "$(cat "$work/labels")" '{number: 7, labels: $l}'; }
code=200
az() { # logs each call's subcommand and resource, keeps the batch body, answers $code
  local a=("$@"); printf '%s\n' "$1 $2 $(printf '%s\n' "${a[@]}" | grep -A1 -x -- --resource | tail -1)" >> "$work/calls"
  while [ $# -gt 0 ]; do [ "$1" = --in-file ] && cp "$2" "$work/batch"; shift; done
  printf '{"count":1,"value":[{"code":%s}]}\n' "$code"
}
labels() { printf '%s' "$1" > "$work/labels"; rm -f "$work/batch" "$work/calls"; }
patch() { jq -c '.[0].body' "$work/batch" 2>/dev/null; }

labels '["needs-triage","ready-for-agent","ready-for-human"]'
host_issue_remove_label 7 ready-for-agent
check "a tag beside others is replaced away, not merged back" \
  '[{"op":"replace","path":"/fields/System.Tags","value":"needs-triage; ready-for-human"}]' "$(patch)"
check "as one PATCH of the work item, json-patch typed" \
  '{"method":"PATCH","uri":"/_apis/wit/workitems/7?api-version=7.1","headers":{"Content-Type":"application/json-patch+json"}}' \
  "$(jq -c '.[0] | del(.body)' "$work/batch" 2>/dev/null)"
check "in one wit batch invoke, no merging update" "devops invoke batch" "$(cat "$work/calls" 2>/dev/null)"

labels '["ready-for-agent"]'
host_issue_remove_label 7 ready-for-agent
check "the last tag is removed" '[{"op":"remove","path":"/fields/System.Tags"}]' "$(patch)"

# A batch answers 200 whatever its request did; the request's own code decides.
labels '["needs-triage","ready-for-agent"]'
code=400 host_issue_remove_label 7 ready-for-agent; rc=$?
check_rc "a refused patch inside a 200 batch is a failure" 1 "$rc"

# A host blip on the write is retried once, as every other az call is.
labels '["needs-triage","ready-for-agent"]'
az() { printf '%s\n' "$1" >> "$work/calls"; [ "$(wc -l < "$work/calls")" -gt 1 ] && echo '{"value":[{"code":200}]}'; }
sleep() { :; }
host_issue_remove_label 7 ready-for-agent; rc=$?
check_rc "a failed write that succeeds on retry is a success" 0 "$rc"
check "after two attempts" "devops devops" "$(paste -sd' ' "$work/calls")"

labels '["needs-triage"]'
host_issue_remove_label 7 ready-for-agent; rc=$?
check_rc "an absent tag is a no-op success" 0 "$rc"
check "with no write" "" "$(cat "$work/batch" "$work/calls" 2>/dev/null)"

finish
