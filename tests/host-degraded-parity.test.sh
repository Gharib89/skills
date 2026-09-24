#!/usr/bin/env bash
# Parity cases for the degraded answers the host contract in `_lib.sh`
# documents: an answer an adapter gives where its host cannot say more, which
# on Azure DevOps is the everyday answer. The rows are the ones #267 holds to a
# parity case, each a degraded answer a mechanic acts on. No mechanic branches
# on the detected host, so each case feeds that answer as a fixture over the
# Host fake (tests/host-fake.sh) inside a throwaway checkout whose origin names
# GitHub, and holds the mechanic that acts on it to its documented behaviour.
#
#   host_can_push unknown            preflight warns on stderr and continues
#   host_pr_reviewer_blocked null    poll-pr --reviewer refuses nothing
#   host_pr_set_body silent failure  update-pr-body exits 1 with status null
#   host_pr_set_title silent failure update-pr-title exits 1 with status null
#
# The fifth row, host_workflow_runs non-zero, already has its parity case:
# "a refused run read is unavailable, not a missing run" in
# tests/reviewer-run.test.sh, which this file names rather than duplicates.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
T=$'\t'  # the calls log separates arguments with a tab

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
# preflight's existing-branch check runs `git ls-remote origin`; refusing every
# transport but file keeps it off the network and off git's credential helper.
export GIT_ALLOW_PROTOCOL=file
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git

reset() { rm -f "$SHIP_FAKE"/*; }
mech() { local m=$1; shift; ( cd "$repo" && bash "$scripts/$m.sh" "$@" ); }

# host_can_push. These two run before the profile below is written: with none,
# a preflight that went on past the push check stops at the next one, `profile
# missing`, with exit 1. The reason is the proof it continued, where `false`
# ends the run at exit 2.
reset
printf 'me\n'      > "$SHIP_FAKE/host_identity.1.json"
printf 'unknown\n' > "$SHIP_FAKE/host_can_push.1.json"
out=$(mech preflight none 2>"$work/err"); rc=$?
check_rc "an unknown push permission is not host-unreachable" 1 "$rc"
check "preflight warns on stderr" \
  'push permission could not be proven on github; the merge will tell' \
  "$(grep '^push permission' "$work/err")"
check "and goes on to the profile check" 'profile missing' \
  "$(jq -r '.reasons[0] | split(":")[0]' <<<"$out")"

reset
printf 'me\n'    > "$SHIP_FAKE/host_identity.1.json"
printf 'false\n' > "$SHIP_FAKE/host_can_push.1.json"
out=$(mech preflight none 2>"$work/err"); rc=$?
check_rc "a false push permission ends preflight" 2 "$rc"
check "as host-unreachable" 'host-unreachable: me cannot push to owner/repo; switch to the account with access' \
  "$(jq -r '.reasons | join(";")' <<<"$out")"
check "with no warning" '' "$(grep '^push permission' "$work/err")"

# host_pr_reviewer_blocked. Azure DevOps answers null, its notices arriving as
# review rows instead: with no row either, the since rule has nothing to refuse
# on, and the window runs as for a reviewer that simply has not posted.
mkdir -p "$repo/docs/agents"
cat > "$repo/docs/agents/ship.md" <<'EOF'
## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-request
Request: None.
Cap: 3
Gating: no

## Coding standards
EOF
reset
printf '{"number":7,"body":"","head_sha":"deadbee","state":"open","mergeable":"clean"}\n' \
  > "$SHIP_FAKE/host_pr_get.1.json"
printf '[]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
printf '{"on_head":[],"all":[],"total":0}\n' > "$SHIP_FAKE/host_pr_reviews.1.json"
echo null > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
out=$(mech poll-pr 7 --reviewer copilot --since 2026-09-23T14:22:34Z --timeout 0 --interval 1); rc=$?
check "the blocked lookup is asked for the reviewer's login" \
  "host_pr_reviewer_blocked${T}7${T}copilot-pull-request-reviewer[bot]" \
  "$(grep '^host_pr_reviewer_blocked' "$SHIP_FAKE/calls" | sort -u)"
check "a null blocked lookup refuses nothing" 'null null' \
  "$(jq -r '[.refused_by, .reviewer_blocked] | map(tostring) | join(" ")' <<<"$out")"
check_rc "and the window closes at --timeout" 1 "$rc"
check "with nothing landed" 'null false' \
  "$(jq -r '[.landed_by, .done] | map(tostring) | join(" ")' <<<"$out")"
rm -rf "$repo/docs"

# host_pr_set_body and host_pr_set_title. `az` reports no HTTP status, so a
# failed write there prints nothing: the verdict is still a failure, and its
# status is null rather than a number carried over from somewhere else.
printf 'a section\n' > "$work/body"
reset
: > "$SHIP_FAKE/host_pr_set_body.1.fail"
out=$(mech update-pr-body 7 --section Review --body-file "$work/body" 2>/dev/null); rc=$?
check_rc "a silent body write failure exits 1" 1 "$rc"
check "with status null" '{"error":"PR body update failed","status":null}' "$(jq -c . <<<"$out")"

reset
printf '{"title":"fix(ship): old title"}\n' > "$SHIP_FAKE/host_pr_get.1.json"
: > "$SHIP_FAKE/host_pr_set_title.1.fail"
out=$(mech update-pr-title 7 --title "fix(ship): new title" 2>/dev/null); rc=$?
check_rc "a silent title write failure exits 1" 1 "$rc"
check "with status null" '{"error":"PR title update failed","status":null}' "$(jq -c . <<<"$out")"

finish
