#!/usr/bin/env bash
# host_branch_protections (#1103): what the host enforces on a branch, read-only.
# The GitHub adapter reads the classic protection and the branch's rulesets, the
# Azure DevOps one the branch's policies. An unreadable answer is `unknown`,
# never none. Each adapter's transport is stubbed (`api`, `az`), so no case
# reaches a host; the real answers behind the stubs were measured on 2026-11-06:
# this repo's classic read answers 404 "Branch not protected", a protected
# branch the token cannot administer answers a bare 404 "Not Found", and a free
# private repo answers 403 "Upgrade to GitHub Pro".
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

read_github() { # <classic: json | notprotected | 403 | hidden> <rules: json | fail> -> compact answer
  (
    SHIP_OWNER=o SHIP_REPO=r
    source skills/ship/scripts/_lib.sh; source skills/ship/scripts/host/github.sh
    api() { # the adapter's two reads, answered by endpoint; stderr carries gh's message
      case $1 in
        */protection) case $CLASSIC in
          notprotected) echo 'gh: Branch not protected (HTTP 404)' >&2; return 1 ;;
          403) echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; return 1 ;;
          hidden) echo 'gh: Not Found (HTTP 404)' >&2; return 1 ;;
          *) echo "$CLASSIC" ;; esac ;;
        */rules/branches/*) [ "$RULES" != fail ] || return 1
          printf '%s\n' "$*" > "$LOG"; jq -c '.[]' <<<"$RULES" ;; # --paginate --jq '.[]': one rule per line
      esac
    }
    LOG=$work/rules-call CLASSIC=$1 RULES=$2 host_branch_protections "${3:-main}" | jq -c .
  )
}
copilot='{"type":"copilot_code_review","parameters":{}}'

check "no protection and only the copilot ruleset is unprotected" \
  '{"branch":"main","protected":"no","required_checks":[],"required_reviews":0,"bypass":"n/a"}' \
  "$(read_github notprotected "[$copilot]")"
classic='{"required_status_checks":{"checks":[{"context":"check-full"},{"context":"bump-guard"}]},"required_pull_request_reviews":{"required_approving_review_count":2},"enforce_admins":{"enabled":false}}'
check "classic protection reports its checks, reviews and an admin bypass" \
  '{"branch":"main","protected":"yes","required_checks":["bump-guard","check-full"],"required_reviews":2,"bypass":"yes"}' \
  "$(read_github "$classic" '[]')"
check "enforce_admins closes the bypass" '"no"' \
  "$(read_github "${classic/\"enabled\":false/\"enabled\":true}" '[]' | jq -c .bypass)"
rule='[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"ci"}]}},{"type":"pull_request","parameters":{"required_approving_review_count":1}}]'
check "a ruleset alone protects, and its bypass actors are unread" \
  '{"branch":"main","protected":"yes","required_checks":["ci"],"required_reviews":1,"bypass":"unknown"}' \
  "$(read_github notprotected "$rule")"
check "a refused classic read (403) is unknown, never none" \
  '{"branch":"main","protected":"unknown","required_checks":"unknown","required_reviews":"unknown","bypass":"unknown"}' \
  "$(read_github 403 '[]')"
check "a bare 404 on a branch the token cannot administer is unknown too" '"unknown"' \
  "$(read_github hidden '[]' | jq -c .protected)"
check "an unreadable rules read cannot say none" '"unknown"' "$(read_github notprotected fail | jq -c .protected)"
read_github notprotected "[$copilot]" release/x >/dev/null
check "a slash in the branch is encoded and the rules read is paged" \
  'repos/o/r/rules/branches/release%2Fx --paginate --jq .[]' "$(cat "$work/rules-call")"
check "a rule on a later page still protects" '"yes"' \
  "$(read_github notprotected "[$copilot,{\"type\":\"pull_request\",\"parameters\":{\"required_approving_review_count\":1}}]" | jq -c .protected)"
check "a ruleset still shows when the classic read is refused, its fields unknown" \
  '{"branch":"main","protected":"yes","required_checks":"unknown","required_reviews":"unknown","bypass":"unknown"}' \
  "$(read_github 403 "$rule")"

legacy='{"required_status_checks":{"contexts":["old-ci"],"checks":[]},"enforce_admins":{"enabled":true},"required_pull_request_reviews":{"bypass_pull_request_allowances":{"users":[{"login":"x"}]}}}'
check "legacy contexts count as required checks" '["old-ci"]' "$(read_github "$legacy" '[]' | jq -c .required_checks)"
check "a bypass allowance opens the bypass even with enforce_admins" '"yes"' "$(read_github "$legacy" '[]' | jq -c .bypass)"

read_ado() { # <policy-list json | fail> -> compact answer
  (
    SHIP_ORG_URL=https://dev.azure.com/o SHIP_PROJECT=p SHIP_REPO=r
    source skills/ship/scripts/_lib.sh; source skills/ship/scripts/host/ado.sh
    az() { case "$1 $2" in
      "repos show") echo '{"id":"rid","defaultBranch":"refs/heads/main"}' ;;
      "repos policy") [ "$POLICIES" != fail ] && echo "$POLICIES" || return 1 ;; esac; }
    sleep() { :; }
    POLICIES=$1 host_branch_protections main | jq -c .
  )
}
pol='[{"isEnabled":true,"isBlocking":true,"type":{"id":"fa4e907d-c16b-4a4c-9dfa-4906e5d171dd"},"settings":{"minimumApproverCount":2,"scope":[{"repositoryId":"rid","refName":"refs/heads/main","matchKind":"Exact"}]}},
{"isEnabled":true,"isBlocking":true,"type":{"id":"0609b952-1397-4640-95ec-e00a01b2c241"},"settings":{"displayName":"build","scope":[{"repositoryId":"rid","refName":"refs/heads/main","matchKind":"Exact"}]}},
{"isEnabled":true,"isBlocking":false,"type":{"id":"cbdc66da-9728-4af8-aada-9a5a32e4a226"},"settings":{"statusName":"advisory","scope":[{"repositoryId":"rid","refName":"refs/heads/main","matchKind":"Exact"}]}},
{"isEnabled":false,"isBlocking":true,"type":{"id":"fa4e907d-c16b-4a4c-9dfa-4906e5d171dd"},"settings":{"minimumApproverCount":9,"scope":[{"repositoryId":"rid","refName":"refs/heads/main","matchKind":"Exact"}]}}]'
check "an empty policy list is unprotected" \
  '{"branch":"main","protected":"no","required_checks":[],"required_reviews":0,"bypass":"n/a"}' "$(read_ado '[]')"
check "enabled blocking policies are reported, the others ignored" \
  '{"branch":"main","protected":"yes","required_checks":["build"],"required_reviews":2,"bypass":"unknown"}' "$(read_ado "$pol")"
check "a build policy with no display name adds no null" '[]' \
  "$(read_ado '[{"isEnabled":true,"isBlocking":true,"type":{"id":"0609b952-1397-4640-95ec-e00a01b2c241"},"settings":{"scope":[{"repositoryId":"rid","refName":"refs/heads/main","matchKind":"Exact"}]}}]' | jq -c .required_checks)"
rv='"type":{"id":"fa4e907d-c16b-4a4c-9dfa-4906e5d171dd"},"isEnabled":true,"isBlocking":true'
check "a prefix scope and a default-branch scope apply, another branch's scope does not" '3' \
  "$(read_ado "[{$rv,\"settings\":{\"minimumApproverCount\":3,\"scope\":[{\"repositoryId\":null,\"refName\":\"refs/heads/ma\",\"matchKind\":\"Prefix\"}]}},
  {$rv,\"settings\":{\"minimumApproverCount\":2,\"scope\":[{\"repositoryId\":\"rid\",\"matchKind\":\"DefaultBranch\"}]}},
  {$rv,\"settings\":{\"minimumApproverCount\":9,\"scope\":[{\"repositoryId\":\"rid\",\"refName\":\"refs/heads/other\",\"matchKind\":\"Exact\"}]}},
  {$rv,\"settings\":{\"minimumApproverCount\":8,\"scope\":[{\"repositoryId\":\"elsewhere\",\"refName\":\"refs/heads/main\",\"matchKind\":\"Exact\"}]}}]" | jq -c .required_reviews)"
check "a refused policy read is unknown, never none" \
  '{"branch":"main","protected":"unknown","required_checks":"unknown","required_reviews":"unknown","bypass":"unknown"}' "$(read_ado fail)"

finish
