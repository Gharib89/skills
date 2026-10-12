#!/usr/bin/env bash
# read-issue marks each comment `writer`: true where its author has write access
# to the repo, false where not, null where the host cannot answer. Ship's spec
# precedence lets only a `writer: true` comment supersede the issue body, so a
# null must stay null and never read as either answer. Each adapter is sourced
# with its transport (`api` on GitHub, `invoke` on Azure DevOps) redefined to
# answer a fixture, so the projection is the subject with no host behind it;
# read-issue itself is driven over the Host fake.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
FIXTURE=$work/fixture.json

# GitHub: the collaborator permission route is the host's answer, `push` being
# write access. `author_association` is not: an org MEMBER or an outside
# COLLABORATOR can hold read access only, so the fixture gives them both that
# association and push false. The stub answers a route from a file named for
# it, applying the `--jq` filter the adapter hands gh, as gh would, and fails
# where no file exists; every route asked is logged.
github=$(
  SHIP_OWNER=o SHIP_REPO=r
  source skills/ship/scripts/_lib.sh
  source skills/ship/scripts/host/github.sh
  api() {
    printf '%s\n' "$1" >> "$work/routes"
    local f; f="$work/route.$(printf '%s' "$1" | tr '/' '_')"
    [ -f "$f" ] && jq -c "${!#}" "$f"
  }
  printf '[%s]\n' '
    {"user":{"login":"admin"},"body":"a","created_at":"t","author_association":"OWNER"},
    {"user":{"login":"reader"},"body":"r","created_at":"t","author_association":"MEMBER"},
    {"user":{"login":"app[bot]"},"body":"b","created_at":"t","author_association":"NONE"},
    {"user":{"login":"gone"},"body":"g","created_at":"t","author_association":"COLLABORATOR"},
    {"user":{"login":"admin"},"body":"again","created_at":"t","author_association":"OWNER"}' \
    > "$work/route.repos_o_r_issues_1_comments"
  perm() { printf '{"permission":"%s","user":{"permissions":{"push":%s}}}\n' "$2" "$3" \
    > "$work/route.repos_o_r_collaborators_$1_permission"; }
  perm admin admin true; perm reader read false; perm 'app%5Bbot%5D' none false
  host_issue_comments 1 | jq -c 'map(if has("writer") then .writer else "absent" end)'
)
check "GitHub: push access writes; read and none do not; a failed permission call is null" \
  '[true,false,false,null,true]' "$github"
check "GitHub: one permission call per distinct author, the login URI-encoded" \
  'repos/o/r/collaborators/admin/permission
repos/o/r/collaborators/app%5Bbot%5D/permission
repos/o/r/collaborators/gone/permission
repos/o/r/collaborators/reader/permission' "$(grep collaborators "$work/routes" | sort)"

# Azure DevOps: write access needs the author's identity descriptor, which only
# vssps.dev.azure.com serves, outside the cloud sandbox's allowlist, so the
# adapter cannot answer and every comment, a project admin's included, is null.
ado=$(
  SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
  source skills/ship/scripts/_lib.sh
  source skills/ship/scripts/host/ado.sh
  invoke() { cat "$FIXTURE"; }
  printf '%s\n' '{"comments":[
    {"createdBy":{"uniqueName":"admin@x"},"text":"a","createdDate":"t"},
    {"createdBy":{"uniqueName":"reader@x"},"text":"r","createdDate":"t"}]}' > "$FIXTURE"
  host_issue_comments 1 | jq -c 'map(if has("writer") then .writer else "absent" end)'
)
check "Azure DevOps: every comment is null, the host cannot answer" '[null,null]' "$ado"

# read-issue carries each adapter's answer to its stdout unchanged.
repo=$work/repo; export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
printf '{"number":7,"title":"t","body":"","state":"open","is_pr":false,"labels":[],"assignees":[]}\n' \
  > "$SHIP_FAKE/host_issue_get.1.json"
printf '[]\n' > "$SHIP_FAKE/host_issue_blockers_open.1.json"
printf '[%s]\n' '{"author":"w","body":"a","created_at":"t","writer":true},
  {"author":"n","body":"b","created_at":"t","writer":false},
  {"author":"u","body":"c","created_at":"t","writer":null}' > "$SHIP_FAKE/host_issue_comments.1.json"
check "read-issue: writer, non-writer and unanswered pass through" '[true,false,null]' \
  "$(cd "$repo" && bash "$scripts/read-issue.sh" 7 2>/dev/null \
    | jq -c '.comments | map(if has("writer") then .writer else "absent" end)')"

finish
