#!/usr/bin/env bash
# Removing a GitHub label (#636): the adapter reads the labels before its
# DELETE, because a DELETE 404s the same way whether the label was gone or the
# call failed. A read that failed is no verdict either, so the removal fails
# rather than skip the DELETE and report success. Beside
# tests/ado-remove-label.test.sh; `api` and `host_issue_get` are stubbed, so no
# case here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
# The adapter reads these at source time; no call in this file reaches a host.
SHIP_OWNER=owner SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host_issue_get() { [ -f "$work/labels" ] || return 1; jq -n --argjson l "$(cat "$work/labels")" '{number: 7, labels: $l}'; }
api() { printf '%s\n' "$*" >> "$work/calls"; }
labels() { rm -f "$work/labels" "$work/calls"; [ -z "$1" ] || printf '%s' "$1" > "$work/labels"; }

labels '["needs-triage","ready-for-agent"]'
host_issue_remove_label 7 ready-for-agent; rc=$?
check_rc "a present label is removed" 0 "$rc"
check "by one DELETE of that label" "-X DELETE repos/owner/repo/issues/7/labels/ready-for-agent" "$(cat "$work/calls" 2>/dev/null)"

labels '["needs-triage"]'
host_issue_remove_label 7 ready-for-agent; rc=$?
check_rc "an absent label is a no-op success" 0 "$rc"
check "with no DELETE" "" "$(cat "$work/calls" 2>/dev/null)"

labels ''
host_issue_remove_label 7 ready-for-agent; rc=$?
check_rc "a label read that failed fails the removal" 1 "$rc"
check "with no DELETE" "" "$(cat "$work/calls" 2>/dev/null)"

finish
