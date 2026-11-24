#!/usr/bin/env bash
# host_pr_checks() on Azure DevOps keeps a policy evaluation and a PR status
# apart (#1361): the host contract lets a name answer more than one row and
# grades it green only when every row of it is success, so a collapse by name
# let a green row hide a red one. Statuses still collapse per context, newest
# first. The adapter is sourced and its transport functions, `azx` and
# `invoke`, are redefined as shell functions answering fixtures, so the
# projection is the subject with no `az` behind it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
# The adapter reads these at source time; `azx` and `invoke` are stubbed below.
SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
source skills/ship-run/scripts/_lib.sh
source skills/ship-run/scripts/host/ado.sh

# $POLICIES and $STATUSES are the two fixtures each case sets.
azx() { printf '%s\n' "$POLICIES"; }
invoke() { printf '%s\n' "$STATUSES"; }
policy() { # <name> <evaluation status> [<enabled>]
  jq -nc --arg n "$1" --arg s "$2" --argjson e "${3:-true}" \
    '{status: $s, configuration: {isEnabled: $e, settings: {displayName: $n}, type: {displayName: "Build"}}}'
}
status() { # <name> <state> <created>
  jq -nc --arg n "$1" --arg s "$2" --arg c "$3" \
    '{state: $s, creationDate: $c, context: {genre: "ci", name: $n}}'
}
rows() { jq -c '[.[] | "\(.name)=\(.status)"] | sort | join(" ")' <<<"$1"; }
run() { host_pr_checks 7 abc123; }

POLICIES="[$(policy ci/build rejected)]"
STATUSES="{\"value\": [$(status build succeeded 2026-11-24T10:00:00Z)]}"
check "a failing policy beside a succeeded status of its name keeps both rows" \
  '"ci/build=failure ci/build=success"' "$(rows "$(run)")"

POLICIES="[$(policy Build approved), $(policy Build rejected)]"
STATUSES='{"value": []}'
check "two policies of one name keep both rows" \
  '"Build=failure Build=success"' "$(rows "$(run)")"

POLICIES='[]'
STATUSES="{\"value\": [$(status lint pending 2026-11-24T10:00:00Z), $(status lint succeeded 2026-11-24T10:05:00Z),
  $(status docs notApplicable 2026-11-24T10:00:00Z)]}"
check "status re-posts collapse to the newest and a notApplicable status has no row" \
  '"ci/lint=success"' "$(rows "$(run)")"

finish
