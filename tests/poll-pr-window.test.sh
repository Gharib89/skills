#!/usr/bin/env bash
# poll-pr's window across calls: the tool-time cap and its cursor, a host read
# that gives no answer, and the --since a reviewer's request supplies by default.
#
# Driven end to end over the Host fake inside a throwaway checkout whose origin
# names GitHub, on the `plain` block (the host's own request call, no run to
# await) and `claude` (a comment transport). SHIP_CALL_CAP is set to seconds so
# a "540 s" call is a two-second one; --interval 1 keeps every case short.
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

### plain

Login: claude[bot]
Trigger: on-request
Request: None.
Cap: 2
Gating: no

### claude

Login: claude[bot]
Trigger: on-request
Request: comment @claude
Workflow: .github/workflows/claude-review.yml
Cap: 2
Gating: no

## Coding standards
PROFILE

since=2026-09-17T11:58:00Z
round() { # <submitted_at>
  jq -cn --arg t "$1" '{id: "1", login: "claude[bot]", state: "comment", substantive: true,
    submitted_at: $t, body: "- a finding"}'
}
landed=$(jq -cn --argjson r "$(round 2026-09-17T12:00:00Z)" '{on_head: [], all: [$r], total: 1}')
earlier=$(jq -cn --argjson r "$(round 2026-09-17T11:00:00Z)" '{on_head: [], all: [$r], total: 1}')
empty='{"on_head":[],"all":[],"total":0}'

reset() {
  rm -f "${SHIP_FAKE:?}"/*
  jq -cn '{number: 7, url: "https://example.invalid/7", title: "t", body: "",
    head_sha: "deadbee", head_ref: "fix/x-7", base_ref: "main", state: "open", mergeable: "clean"}' \
    > "$SHIP_FAKE/host_pr_get.1.json"
  echo null > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
  echo '[]' > "$SHIP_FAKE/host_pr_checks.1.json"
}
# poll <flag>...: the reviewer WHO (plain), the call cap CAP seconds (540)
poll() { ( cd "$repo" && SHIP_CALL_CAP=${CAP:-540} bash "$mech" 7 --reviewer "${WHO:-plain}" --interval 1 "$@" ); }
n() { cat "$SHIP_FAKE/$1.n" 2>/dev/null || echo 0; }

# The cap. The reviewer's round is five reads out, so the first call (cap 2 s)
# ends with the window open and hands back its cursor; the second resumes it,
# lands the round and counts its waiting from the first call.
reset
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.5.json"
t0=$(date +%s)
out=$(CAP=2 poll --since "$since"); rc=$?
t1=$(date +%s)
check_rc "a window still open at the cap answers exit 1" 1 "$rc"
check "and says it is pending" pending "$(jq -r .status <<<"$out")"
check "and is not done" false "$(jq -r .done <<<"$out")"
check "and carries a cursor" true "$(jq '(.cursor | type) == "string" and (.cursor | length) > 0' <<<"$out")"
check "and keeps the snapshot shape" deadbee "$(jq -r .head_sha <<<"$out")"
check "the call held the tool no longer than its cap, plus one read" true "$([ $((t1 - t0)) -le 3 ] && echo true || echo false)"
cursor=$(jq -r .cursor <<<"$out")
out=$(CAP=2 poll --cursor "$cursor"); rc=$?
check_rc "the resumed call lands the round" 0 "$rc"
check "by the since the cursor carried" since "$(jq -r .landed_by <<<"$out")"
check "and a done answer has no status" false "$(jq 'has("status")' <<<"$out")"
check "waited_s counts from the first call" true "$(jq '.waited_s >= 3' <<<"$out")"

reset
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(CAP=1 poll --since "$since" --brief); rc=$?
check_rc "--brief at the cap is exit 1" 1 "$rc"
check "--brief answers pending with a cursor and its rounds" "pending true array" \
  "$(jq -r '"\(.status) \(.cursor | length > 0) \(.rounds | type)"' <<<"$out")"

# A pending answer's window is still open, so it grades no cause: the awaited
# run being in_progress is not an infra-error, and no round yet is not silence.
reset
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
jq -cn '[{status: "in_progress", conclusion: null, created_at: "2026-09-17T11:59:00Z",
          url: "https://example.invalid/runs/10", title: "t"}]' > "$SHIP_FAKE/host_workflow_runs.1.json"
out=$(WHO=claude CAP=1 poll --since "$since" --timeout 60); rc=$?
check "a pending answer beside an in-progress run" "pending in_progress null" \
  "$(jq -r '[.status, .reviewer_run.status, (.not_reviewed | tojson)] | join(" ")' <<<"$out")"
out=$(WHO=claude CAP=1 poll --since "$since" --timeout 60 --brief)
check "and the brief answer too" "pending null" "$(jq -r '[.status, (.not_reviewed | tojson)] | join(" ")' <<<"$out")"
reset
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(CAP=1 poll --since "$since")
check "and a pending answer with no run to read" null "$(jq -c .not_reviewed <<<"$out")"

# A cursor is the window: it brings its own deadline and since, and refuses a
# second opinion on either.
cursor=$(jq -r .cursor <<<"$out")
refuse() { # <case> <error-fragment> <flags...>
  local c=$1 f=$2 o r; shift 2
  o=$(poll "$@" 2>/dev/null); r=$?
  check_rc "$c is tooling" 2 "$r"
  check "$c names why" true "$(jq --arg f "$f" '.error | contains($f)' <<<"$o")"
}
refuse "--cursor with --since" "drop --since and --timeout" --cursor "$cursor" --since "$since"
refuse "--cursor with --timeout" "drop --since and --timeout" --cursor "$cursor" --timeout 5
refuse "a cursor that does not read" "--cursor does not read" --cursor garbage
refuse "a cursor with no deadline" "--cursor does not read" --cursor "$(printf '{"since":"%s"}' "$since" | base64 -w0)"
o=$(cd "$repo" && bash "$mech" 7 --cursor "$cursor" 2>/dev/null); r=$?
check_rc "a cursor that holds a --since, with no --reviewer, is tooling" 2 "$r"

# A read with no answer. The fake's .fail with no .status is a dropped
# connection: no HTTP status for ship_poll_read to find.
fail() { : > "$SHIP_FAKE/$1.$2.fail"; }
reset
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.2.json"
fail host_pr_get 2
cp "$SHIP_FAKE/host_pr_get.1.json" "$SHIP_FAKE/host_pr_get.3.json"
out=$(poll --since "$since"); rc=$?
check_rc "one read that gave no answer mid-window keeps the poll going" 0 "$rc"
check "and the round still lands" since "$(jq -r .landed_by <<<"$out")"
check "the failed read was read again" 3 "$(n host_pr_get)"

# The first read gives no answer and the call's cap is already spent: the
# pending answer is still JSON, with no head read yet.
reset
fail host_pr_get 1
out=$(CAP=0 poll --since "$since" 2>/dev/null); rc=$?
check_rc "a cap spent before the first answered read is pending, exit 1" 1 "$rc"
check "and its answer is JSON saying so" pending "$(jq -r .status <<<"$out" 2>/dev/null)"

# Two in a row, an answer, two more: the count restarts at an answered pass.
reset
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.2.json"
fail host_pr_checks 1; fail host_pr_checks 2; echo '[]' > "$SHIP_FAKE/host_pr_checks.3.json"
fail host_pr_checks 4; fail host_pr_checks 5; echo '[]' > "$SHIP_FAKE/host_pr_checks.6.json"
out=$(poll --since "$since"); rc=$?
check_rc "two failures, an answer and two more do not make three in a row" 0 "$rc"
check "and the round lands" since "$(jq -r .landed_by <<<"$out")"

reset
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.1.json"
fail host_pr_checks 1
out=$(poll --since "$since" 2>/dev/null); rc=$?
check_rc "three failures in a row are exit 2" 2 "$rc"
check "naming the read" true "$(jq '.error | contains("cannot read checks")' <<<"$out")"
check "after three passes, not one" 3 "$(n host_pr_checks)"

reset
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.1.json"
fail host_pr_checks 1
out=$(poll --since "$since" --timeout 1 2>/dev/null); rc=$?
check_rc "a window that ends while the reads still fail is exit 2" 2 "$rc"
check "before the third failure" 2 "$(n host_pr_checks)"

# A refusal that carries a status is the host's answer, and ends the poll at once.
reset
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.1.json"
rm "$SHIP_FAKE/host_pr_checks.1.json"; fail host_pr_checks 1; printf 404 > "$SHIP_FAKE/host_pr_checks.1.status"
out=$(poll --since "$since" 2>/dev/null); rc=$?
check_rc "a read the host refused with a status is exit 2" 2 "$rc"
check "on the first read" 1 "$(n host_pr_checks)"
check "naming it" true "$(jq '.error | contains("cannot read checks")' <<<"$out")"

# The default --since: the host's own word for when this reviewer was asked.
reset
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$since" > "$SHIP_FAKE/host_pr_requested_at.1.json"
out=$(poll --timeout 0); rc=$?
check_rc "no --since: the host's request instant lands a round after it" 0 "$rc"
check "by the since rule" since "$(jq -r .landed_by <<<"$out")"
check "the host was asked for the reviewer's login, with no phrase" \
  "$(printf 'host_pr_requested_at\t7\tclaude[bot]')" "$(grep '^host_pr_requested_at' "$SHIP_FAKE/calls")"

reset
printf '%s\n' "$earlier" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$since" > "$SHIP_FAKE/host_pr_requested_at.1.json"
out=$(poll --timeout 0); rc=$?
check_rc "a round submitted before that instant does not land" 1 "$rc"
check "so no round is credited" null "$(jq -c .landed_by <<<"$out")"

reset
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$since" > "$SHIP_FAKE/host_pr_requested_at.1.json"
WHO=claude poll --timeout 0 >/dev/null
check "a comment transport asks with its phrase" \
  "$(printf 'host_pr_requested_at\t7\tclaude[bot]\t@claude')" "$(grep '^host_pr_requested_at' "$SHIP_FAKE/calls")"

reset
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$since" > "$SHIP_FAKE/host_pr_requested_at.1.json"
poll --since 2026-09-17T11:59:00Z --timeout 0 >/dev/null
check "an explicit --since asks the host nothing" '' "$(grep '^host_pr_requested_at' "$SHIP_FAKE/calls")"

reset
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "yesterday" > "$SHIP_FAKE/host_pr_requested_at.1.json"
out=$(poll --timeout 0 2>/dev/null); rc=$?
check_rc "an instant that is not UTC ISO-8601 is the refusal" 2 "$rc"
reset
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.1.json"
: > "$SHIP_FAKE/host_pr_requested_at.1.fail"
out=$(poll --timeout 0 2>/dev/null); rc=$?
check_rc "a host with no instant is the refusal" 2 "$rc"
check "which is the rule's own line" \
  'plain is on-request, whose rounds land by time: --since <iso> is required' "$(jq -r .error <<<"$out")"

# --brief --full open: every round and every open thread whole.
reset
big=$(printf 'w%.0s' $(seq 1 600))
jq -cn --arg b "$big" '{on_head: [], total: 1, all: [{id: "1", login: "claude[bot]", state: "comment",
  substantive: true, submitted_at: "2026-09-17T12:00:00Z", body: $b}]}' > "$SHIP_FAKE/host_pr_reviews.1.json"
jq -cn --arg b "$big" '[{id: "t1", resolved: false, replied: false, author: "claude", path: "x.sh", body: ($b + "\n\nmore")}]' \
  > "$SHIP_FAKE/host_pr_threads.1.json"
out=$(poll --since "$since" --brief --full open)
check "--full open returns the round whole" 600 "$(jq '.rounds[0].body | length' <<<"$out")"
check "--full open returns the open thread's lead whole" 606 "$(jq '.threads[0].lead | length' <<<"$out")"
out=$(poll --since "$since" --brief)
check "without it the same round is cut and marked" 215 "$(jq '.rounds[0].body | length' <<<"$out")"

finish
