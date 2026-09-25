#!/usr/bin/env bash
# poll-pr's `not_reviewed`: the cause it observed when the awaited reviewer's
# window closed with no round admitted, which is the reason a run reports as
# `not reviewed: <reason>`, never one it guesses. The run-derived causes
# (`infra-error`, a run never created, an unreadable run read) are cased in
# tests/reviewer-run.test.sh and a refusal (`blocked`) in
# tests/reviewer-refused.test.sh, beside the window behaviour each one comes
# from; this file holds the rest and the flags the free-round poll used to take.
#
# Driven end to end over the Host fake and a throwaway repo whose origin names
# GitHub, so the mechanic's own loop is the subject: no case reaches a host.
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
cat > "$repo/docs/agents/ship.md" <<'PROFILE'
## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-request
Request: None.
Workflow: None.
Cap: 3
Gating: no
Fallback-for: None.

### claude

Login: claude[bot]
Trigger: on-request
Request: comment @claude
Workflow: .github/workflows/claude-review.yml
Cap: 2
Gating: no
Fallback-for: copilot

### pusher

Login: copilot-pull-request-reviewer[bot]
Trigger: on-push
Request: None.
Workflow: None.
Cap: None.
Gating: no
Fallback-for: None.

## Coding standards
PROFILE

login='copilot-pull-request-reviewer[bot]'
since=2026-09-25T10:00:00Z
round=$(jq -cn --arg l "$login" \
  '{id: "2", login: $l, state: "comment", submitted_at: "2026-09-25T10:05:00Z", body: "- a finding"}')

reset() {
  rm -f "$SHIP_FAKE"/*
  pr_state clean
  printf '[]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
  printf 'me\n' > "$SHIP_FAKE/host_identity.1.json"
  printf '{"on_head":[],"all":[],"total":0}\n' > "$SHIP_FAKE/host_pr_reviews.1.json"
  echo null > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
}
pr_state() { # <mergeable>
  jq -cn --arg m "$1" '{number: 7, url: "https://example.invalid/7", title: "t", body: "",
    head_sha: "deadbee", head_ref: "fix/x-7", base_ref: "main", state: "open", mergeable: $m}' \
    > "$SHIP_FAKE/host_pr_get.1.json"
}
landed() {
  jq -cn --argjson r "$round" '{on_head: [$r], all: [$r], total: 1}' > "$SHIP_FAKE/host_pr_reviews.1.json"
}
poll() { ( cd "$repo" && bash "$mech" 7 "$@" ); }

# The window closing on the bound with nothing admitted is the one cause with no
# signal behind it: the reviewer answered nothing inside its bound.
reset
out=$(poll --reviewer copilot --since "$since" --timeout 0 --interval 1); rc=$?
check_rc "a window closed on the bound" 1 "$rc"
check "is silent" silent "$(jq -r .not_reviewed <<<"$out")"

# Under the head rule the same: no round on the current head.
reset
out=$(poll --reviewer pusher --timeout 0 --interval 1)
check "the head rule's closed window is silent too" silent "$(jq -r .not_reviewed <<<"$out")"

# A landed round is a review, whatever else the poll saw.
reset; landed
out=$(poll --reviewer copilot --since "$since" --timeout 0 --interval 1); rc=$?
check_rc "a landed round is done" 0 "$rc"
check "and carries no reason" null "$(jq -r .not_reviewed <<<"$out")"

# Thread state that could not be read leaves every finding in a thread
# unreadable and unanswerable, a landed round's included.
reset; landed
: > "$SHIP_FAKE/host_pr_threads.1.fail"
out=$(poll --reviewer copilot --since "$since" --timeout 0 --interval 1)
check "unreadable threads are unreachable" 'unreachable "unavailable"' \
  "$(jq -r '[.not_reviewed, (.threads|tojson)] | join(" ")' <<<"$out")"

# A conflict closes the window on the PR, not on the reviewer: no reason, and
# the run resolves it and polls again.
reset; pr_state conflict
out=$(poll --reviewer copilot --since "$since" --timeout 60 --interval 30); rc=$?
check_rc "a conflict closes the window" 0 "$rc"
check "with no reason against the reviewer" null "$(jq -r .not_reviewed <<<"$out")"

# A run that concluded skipped, with nothing else for the PR, is the workflow's
# own `if` declining the comment: nothing ran for the request.
reset
jq -cn '[{status: "completed", conclusion: "skipped", created_at: "2026-09-25T10:00:30Z",
          url: "https://example.invalid/runs/10", title: "t"}]' > "$SHIP_FAKE/host_workflow_runs.1.json"
out=$(poll --reviewer claude --since "$since" --timeout 0 --interval 1)
check "a skipped run alone is never-queued" never-queued "$(jq -r .not_reviewed <<<"$out")"

# With no reviewer awaited there is no one to be reviewed.
reset
out=$(poll --timeout 0 --interval 1)
check "without --reviewer the reason is null" null "$(jq -r .not_reviewed <<<"$out")"

# --brief is what the loop reads, so the reason travels in it, and the fields
# the free-round poll answered with are gone from both shapes.
reset
out=$(poll --reviewer copilot --since "$since" --timeout 0 --interval 1 --brief)
check "--brief carries the reason" silent "$(jq -r .not_reviewed <<<"$out")"
check "--brief has no never_queued or degraded" 'false false' \
  "$(jq -r '[(has("never_queued")|tostring), (has("degraded")|tostring)] | join(" ")' <<<"$out")"
out=$(poll --reviewer copilot --since "$since" --timeout 0 --interval 1)
check "nor does the full shape" 'false false' \
  "$(jq -r '[(has("never_queued")|tostring), (has("degraded")|tostring)] | join(" ")' <<<"$out")"

# The free-round flags are gone: an on-request reviewer's opening round is
# round 1 of its first request, so nothing polls for it on its own.
for flag in --free-round '--review-on-push false'; do
  reset
  # shellcheck disable=SC2086  # the flag and its value are two words
  out=$(poll --reviewer copilot --since "$since" $flag); rc=$?
  check_rc "$flag is an unknown flag" 2 "$rc"
  check "reaching no host: $flag" false "$([ -s "$SHIP_FAKE/calls" ] && echo true || echo false)"
done

finish
