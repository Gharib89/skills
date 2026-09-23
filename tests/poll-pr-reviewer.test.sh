#!/usr/bin/env bash
# poll-pr --reviewer <name>: the Reviewer named by its profile block, with the
# login, the landing rule, the run to await and the default bound derived from
# that block rather than passed flag by flag (#235).
#
# Driven end to end over the Host fake inside a throwaway checkout whose origin
# names GitHub, carrying a copy of this repo's own profile plus one on-push block
# the real profile lacks, so the derivation is read off the blocks a real run
# reads. The refusals are asserted to reach no host: no call is recorded.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/poll-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo/docs/agents" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
awk '/^## Coding standards/ {
       print "### pusher\n\nLogin: pusher[bot]\nTrigger: on-push\nRequest: None.\nWorkflow: None.\nCap: None.\nGating: no\nFallback-for: None.\n"
     } { print }' docs/agents/ship.md > "$repo/docs/agents/ship.md"

since=2026-09-17T11:58:00Z
round() { # <login>
  jq -cn --arg l "$1" '{id: "1", login: $l, state: "comment", substantive: true,
    submitted_at: "2026-09-17T12:00:00Z", body: "- a finding"}'
}
reset() { # <login>: one round by that login, landed after $since
  rm -f "$SHIP_FAKE"/*
  jq -cn --argjson r "$(round "$1")" '{on_head: [], all: [$r], total: 1}' \
    > "$SHIP_FAKE/host_pr_reviews.1.json"
  echo null > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
}
poll() { ( cd "$repo" && bash "$mech" 7 --interval 1 "$@" ); }
called() { cut -f1 "$SHIP_FAKE/calls" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//'; }

reset 'copilot-pull-request-reviewer[bot]'
out=$(poll --reviewer copilot --since "$since"); rc=$?
check_rc "copilot's round lands" 0 "$rc"
check "copilot awaits its login under the since rule, no run, the 600 s bound" \
  '{"name":"copilot","login":"copilot-pull-request-reviewer[bot]","rule":"since","await_run":null,"timeout":600}' \
  "$(jq -c .reviewer <<<"$out")"
check "and it lands by time" since "$(jq -r .landed_by <<<"$out")"
check "no workflow run is read for the host's request call" '' \
  "$(grep '^host_workflow_runs' "$SHIP_FAKE/calls")"

reset 'claude[bot]'
out=$(poll --reviewer claude --since "$since"); rc=$?
check_rc "claude's round lands" 0 "$rc"
check "claude awaits its login under the since rule, its workflow run, the 60 s bound" \
  '{"name":"claude","login":"claude[bot]","rule":"since","await_run":".github/workflows/claude-review.yml","timeout":60}' \
  "$(jq -c .reviewer <<<"$out")"
check "the run read names the block's Workflow: and the --since" \
  "host_workflow_runs	.github/workflows/claude-review.yml	$since" \
  "$(grep '^host_workflow_runs' "$SHIP_FAKE/calls" | sort -u)"
check "and the reviewer rides the brief too" claude \
  "$(poll --reviewer claude --since "$since" --brief | jq -r .reviewer.name)"

reset 'claude[bot]'
out=$(poll --reviewer claude --since "$since" --timeout 5)
check "a --timeout given wins over the derived bound" 5 "$(jq -r .reviewer.timeout <<<"$out")"

reset 'pusher[bot]'
jq -cn --argjson r "$(round 'pusher[bot]')" '{on_head: [$r], all: [$r], total: 1}' \
  > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(poll --reviewer pusher); rc=$?
check_rc "an on-push reviewer polls without --since" 0 "$rc"
check "and lands under the head rule, on the 480 s bound" 'head head 480' \
  "$(jq -r '[.reviewer.rule, .landed_by, .reviewer.timeout] | join(" ")' <<<"$out")"

# Refusals: each is exit 2 and each is answered before the host is loaded.
refuse() { # <case> <expected-error> <flags...>
  local c=$1 e=$2 o r; shift 2
  rm -f "$SHIP_FAKE"/*
  o=$(poll "$@" 2>/dev/null); r=$?
  check_rc "$c is tooling" 2 "$r"
  check "$c" "$e" "$(jq -r .error <<<"$o")"
  check "$c reaches no host" '' "$(called)"
}
refuse "a name no block carries lists the names the profile carries" \
  'no ## Reviewers block is named nobody; the profile names: copilot, claude, pusher' \
  --reviewer nobody --since "$since"
refuse "--since with an on-push reviewer is refused" \
  'pusher is on-push, whose rounds land on the head: --since does not apply' \
  --reviewer pusher --since "$since"
refuse "copilot without --since is refused" \
  'copilot is on-request, whose rounds land by time: --since <iso> is required' \
  --reviewer copilot

rm "$repo/docs/agents/ship.md"
refuse "a checkout with no profile is refused" \
  "no ship profile at $(cd "$repo" && git rev-parse --show-toplevel)/docs/agents/ship.md; --reviewer reads it" \
  --reviewer copilot --since "$since"

finish
