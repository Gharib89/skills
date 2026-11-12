#!/usr/bin/env bash
# Unattended selection skips an issue with an open sub-issue: a spec parent is
# numbered before its children, so with the label on it, it would be picked
# first and shipped as one oversized PR. An issue whose sub-issues are all
# closed, and one with none, stay selectable. Driven over the Host fake.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git

# <case-dir> <candidate numbers...>: a fresh fake whose ready list is those
# issues in order, none blocked, and whose sub-issue answers the caller writes.
fresh() {
  rm -rf "$SHIP_FAKE"; mkdir -p "$SHIP_FAKE"
  printf '[]\n' > "$SHIP_FAKE/host_issue_blockers_open.1.json"
  printf '[%s]\n' "$(printf '{"number":%s,"title":"t","created_at":"2026-01-01T00:00:00Z"},' "$@" | sed 's/,$//')" \
    > "$SHIP_FAKE/host_issues_ready.1.json"
}
sel() { ( cd "$repo" && bash "$scripts/select.sh" 2>/dev/null ); }

fresh 10 11
printf '[12]\n' > "$SHIP_FAKE/host_issue_subissues_open.1.json"
printf '[]\n' > "$SHIP_FAKE/host_issue_subissues_open.2.json"
check "a parent with an open sub-issue is skipped for the next candidate" 11 "$(sel | jq -r .selected)"

fresh 10
printf '[]\n' > "$SHIP_FAKE/host_issue_subissues_open.1.json"
check "an issue with no open sub-issue (all closed, or none) is selected" 10 "$(sel | jq -r .selected)"

fresh 10
printf '[12]\n' > "$SHIP_FAKE/host_issue_subissues_open.1.json"
check "a lone parent with an open sub-issue leaves nothing ready" nothing-ready "$(sel | jq -r .reason)"

fresh 10
: > "$SHIP_FAKE/host_issue_subissues_open.1.fail"
check "a failed sub-issue query stops, it never reads as no sub-issues" \
  'blockers-unavailable 10' "$(sel | jq -r '"\(.reason) \(.candidate)"')"

# The adapters answer from the host's own links: GitHub's native sub-issues
# route, and Azure DevOps' child links (Hierarchy-Forward), never the parent
# (Hierarchy-Reverse) or a predecessor (Dependency-Reverse) link.
github=$(
  SHIP_OWNER=o SHIP_REPO=r
  source skills/ship/scripts/_lib.sh
  source skills/ship/scripts/host/github.sh
  api() { printf '%s\n' "$1" > "$work/route"; printf '[{"number":3,"state":"open"},{"number":4,"state":"closed"}]\n' | jq -c "${!#}"; }
  host_issue_subissues_open 9 | jq -c .; cat "$work/route"
)
check "GitHub: the open sub-issues from the native route" '[3]
repos/o/r/issues/9/sub_issues' "$github"

ado=$(
  SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
  source skills/ship/scripts/_lib.sh
  source skills/ship/scripts/host/ado.sh
  _wi_show() { printf '%s\n' '{"relations":[
    {"rel":"System.LinkTypes.Hierarchy-Forward","url":"https://x/_apis/wit/workItems/21"},
    {"rel":"System.LinkTypes.Hierarchy-Forward","url":"https://x/_apis/wit/workItems/22"},
    {"rel":"System.LinkTypes.Hierarchy-Reverse","url":"https://x/_apis/wit/workItems/23"},
    {"rel":"System.LinkTypes.Dependency-Reverse","url":"https://x/_apis/wit/workItems/24"}]}'; }
  host_issue_get() { if [ "$1" = 21 ]; then echo '{"state":"open"}'; else echo '{"state":"closed"}'; fi; }
  host_issue_subissues_open 9 | jq -c .
)
check "Azure DevOps: only an open child link counts" '[21]' "$ado"

finish
