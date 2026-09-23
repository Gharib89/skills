#!/usr/bin/env bash
# poll-pr --reviewer on a comment transport: the window that reviewer's
# workflow run opens. A run of that workflow is attached to the default branch's SHA, so the
# PR head's checks cannot see it, and a window that closed before the round
# landed was indistinguishable from a reviewer that never queued (#203).
#
# Driven end to end over the Host fake and a throwaway repo whose origin names
# GitHub, so the mechanic's own loop is the subject: no case reaches a host.
# Each read answers from a fixture per call in sequence, the last one repeating.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/poll-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
# The profile `--reviewer` reads: `claude` a comment transport, whose run the
# poll awaits, and `plain` the same login on the host's request call, which
# awaits none.
mkdir -p "$repo/docs/agents"
cat > "$repo/docs/agents/ship.md" <<'EOF'
## Reviewers

### claude

Login: claude[bot]
Trigger: on-request
Request: comment @claude
Workflow: .github/workflows/claude-review.yml
Cap: 2
Gating: no

### plain

Login: claude[bot]
Trigger: on-request
Request: None.
Cap: 2
Gating: no

## Coding standards
EOF

title='fix(ship): the PR under review'
round='{"id":"1","login":"claude[bot]","state":"comment","substantive":true,
        "submitted_at":"2026-09-17T12:00:00Z","body":"- a finding"}'
landed=$(jq -cn --argjson r "$round" '{on_head: [], all: [$r], total: 1}')
empty='{"on_head":[],"all":[],"total":0}'
run_row() { # <status> <conclusion> [<title>]
  jq -cn --arg s "$1" --arg c "$2" --arg t "${3:-$title}" \
    '[{status: $s, conclusion: (if $c == "" then null else $c end),
       created_at: "2026-09-17T11:59:00Z", url: "https://example.invalid/runs/9", title: $t}]'
}

reset() {
  rm -f "$SHIP_FAKE"/*
  jq -cn --arg t "$title" '{number: 7, url: "https://example.invalid/7", title: $t, body: "",
    head_sha: "deadbee", head_ref: "fix/x-7", base_ref: "main", state: "open", mergeable: "clean"}' \
    > "$SHIP_FAKE/host_pr_get.1.json"
  echo null > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
}
poll() { # [<reviewer>] [<flag>...]: claude unless the first argument names another
  local r=claude
  case ${1:-} in ''|-*) ;; *) r=$1; shift ;; esac
  ( cd "$repo" && bash "$mech" 7 --reviewer "$r" --since 2026-09-17T11:58:00Z \
    --timeout 0 --interval 1 "$@" )
}
calls() { cat "$SHIP_FAKE/host_$1.n" 2>/dev/null || echo 0; }

# A run still going at the window's end is the case the bug was: the round was
# 2 to 3 minutes out, the window closed, and the run reported the reviewer
# silent. The window now runs to the run's conclusion.
reset
run_row in_progress ''      > "$SHIP_FAKE/host_workflow_runs.1.json"
run_row completed success   > "$SHIP_FAKE/host_workflow_runs.2.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.2.json"
out=$(poll); rc=$?
check_rc "an in_progress run keeps the poll going until the round lands" 0 "$rc"
check "the round that landed past the window is the round" \
  'true since completed' \
  "$(jq -r '[(.done|tostring), .landed_by, .reviewer_run.status] | join(" ")' <<<"$out")"

# The same fixtures on the host's request call, which awaits no run: the window
# closes on the second the timeout names, which is the behaviour the run read
# exists to fix.
reset
run_row in_progress ''      > "$SHIP_FAKE/host_workflow_runs.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.2.json"
out=$(poll plain); rc=$?
check_rc "without a run to await the window still closes at --timeout" 1 "$rc"
check "and the run is not read at all" 'false null' \
  "$(jq -r '[(.done|tostring), (.reviewer_run|tostring)] | join(" ")' <<<"$out")"

# A concluded run buys one more interval for the review row to appear, and one
# only: waiting longer on a run that is over is waiting on nothing.
reset
run_row completed success > "$SHIP_FAKE/host_workflow_runs.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(poll); rc=$?
check_rc "a concluded run with no row yet closes the window after one more poll" 1 "$rc"
check "the extra poll is one" 2 "$(calls pr_reviews)"
check "and the run is on the record" 'false completed success' \
  "$(jq -r '[(.done|tostring), .reviewer_run.status, .reviewer_run.conclusion] | join(" ")' <<<"$out")"

# A failed run is the reviewer's infrastructure, not its silence: the URL is
# what sends the human to the failure. The window it closes is the whole window,
# so this case is driven with minutes still on `--timeout`: a poll that spends
# them is waiting for a round that cannot come.
reset
run_row completed failure > "$SHIP_FAKE/host_workflow_runs.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(poll --timeout 600 --interval 30); rc=$?
check_rc "a failed run closes the window" 1 "$rc"
check "the failure comes back with the run URL" \
  'completed failure https://example.invalid/runs/9' \
  "$(jq -r '[.reviewer_run.status, .reviewer_run.conclusion, .reviewer_run.url] | join(" ")' <<<"$out")"
check "a failed run buys no extra poll" 1 "$(calls pr_reviews)"
check "and none of the window is spent on it" true \
  "$(jq -r '.waited_s < 30' <<<"$out")"

# No run at all: the status the review loop reads as never-queued.
reset
printf '[]\n'             > "$SHIP_FAKE/host_workflow_runs.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(poll)
check "no run since the request reports the none status" 'none null' \
  "$(jq -r '[.reviewer_run.status, (.reviewer_run.conclusion|tostring)] | join(" ")' <<<"$out")"

# The workflow fires on every comment in the repo, so a run belonging to another
# PR is not this reviewer's round and must not hold the window open.
reset
run_row in_progress '' 'another PR entirely' > "$SHIP_FAKE/host_workflow_runs.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(poll)
check "a run for another PR is not this PR's round" 'none' \
  "$(jq -r '.reviewer_run.status' <<<"$out")"
check "and it holds the window open for nothing" 1 "$(calls pr_reviews)"

# The workflow's own `if` answers a comment that was not the request with a
# skipped run, and that run says nothing about the round: the run that did
# something is the one the poll reports, however new the skipped one is.
reset
jq -cn --arg t "$title" '[{status: "completed", conclusion: "success",
     created_at: "2026-09-17T11:59:00Z", url: "https://example.invalid/runs/9", title: $t},
    {status: "completed", conclusion: "skipped",
     created_at: "2026-09-17T11:59:30Z", url: "https://example.invalid/runs/10", title: $t}]' \
  > "$SHIP_FAKE/host_workflow_runs.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(poll)
check "a skipped run does not answer for the one that ran" \
  'success https://example.invalid/runs/9' \
  "$(jq -r '[.reviewer_run.conclusion, .reviewer_run.url] | join(" ")' <<<"$out")"

# A run that is still going outranks one that concluded after it started: the
# round can only come from the live one.
reset
jq -cn --arg t "$title" '[{status: "in_progress", conclusion: null,
     created_at: "2026-09-17T11:59:00Z", url: "https://example.invalid/runs/9", title: $t},
    {status: "completed", conclusion: "success",
     created_at: "2026-09-17T11:59:30Z", url: "https://example.invalid/runs/10", title: $t}]' \
  > "$SHIP_FAKE/host_workflow_runs.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.2.json"
out=$(poll); rc=$?
check_rc "a live run outranks a newer concluded one and holds the window" 0 "$rc"
check "and it is the run reported" 'in_progress https://example.invalid/runs/9' \
  "$(jq -r '[.reviewer_run.status, .reviewer_run.url] | join(" ")' <<<"$out")"

# The host also reports runs it has not started yet (`requested`, `waiting`,
# `pending`, the approval states): every status but `completed` is a run that can
# still deliver, so it holds the window and outranks a concluded one the way
# `queued` does. Here the round lands two polls out, which a concluded run's one
# extra interval does not reach.
reset
jq -cn --arg t "$title" '[{status: "waiting", conclusion: null,
     created_at: "2026-09-17T11:59:00Z", url: "https://example.invalid/runs/9", title: $t},
    {status: "completed", conclusion: "success",
     created_at: "2026-09-17T11:59:30Z", url: "https://example.invalid/runs/10", title: $t}]' \
  > "$SHIP_FAKE/host_workflow_runs.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.2.json"
printf '%s\n' "$landed" > "$SHIP_FAKE/host_pr_reviews.3.json"
out=$(poll); rc=$?
check_rc "an unfinished run in any status holds the window" 0 "$rc"
check "and it outranks a newer concluded run" 'true since waiting' \
  "$(jq -r '[(.done|tostring), .landed_by, .reviewer_run.status] | join(" ")' <<<"$out")"

# The ceiling is what keeps a run that never finishes from holding the window
# forever: past it the poll returns with the run as it stands, which the review
# loop reads as infra-error. Driven against a copy of the mechanic whose ceiling
# is seconds rather than half an hour; everything else is the real mechanic.
reset
cp -R skills/ship/scripts "$work/scripts"
sed -i.bak 's/^ceiling=1800$/ceiling=2/' "$work/scripts/poll-pr.sh"
run_row in_progress '' > "$SHIP_FAKE/host_workflow_runs.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$( cd "$repo" && bash "$work/scripts/poll-pr.sh" 7 --reviewer claude \
  --since 2026-09-17T11:58:00Z --timeout 0 --interval 1 ); rc=$?
check_rc "a run still going at the ceiling closes the window" 1 "$rc"
check "and it comes back as it stands, with its URL" \
  'false in_progress https://example.invalid/runs/9' \
  "$(jq -r '[(.done|tostring), .reviewer_run.status, .reviewer_run.url] | join(" ")' <<<"$out")"

# A read the host refused says nothing about the reviewer, and must not read as
# a run that was never created: the window falls back to the constant and the
# loop reports the host, not silence.
reset
: > "$SHIP_FAKE/host_workflow_runs.1.fail"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(poll); rc=$?
check_rc "a refused run read closes the window at --timeout" 1 "$rc"
check "a refused run read is unavailable, not a missing run" '"unavailable"' \
  "$(jq -c '.reviewer_run' <<<"$out")"
check "and it buys no extra poll" 1 "$(calls pr_reviews)"

# An answer the filter cannot walk is the same nothing as a refused read: the
# mechanic still prints one JSON object, which is what the caller parses.
reset
printf '"not a list of runs"\n' > "$SHIP_FAKE/host_workflow_runs.1.json"
printf '%s\n' "$empty" > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(poll 2>/dev/null); rc=$?
check_rc "an unreadable run payload closes the window" 1 "$rc"
check "and reads as unavailable, on one JSON object" '"unavailable"' \
  "$(jq -c '.reviewer_run' <<<"$out")"

# The Azure DevOps adapter has no such read, and answers the way it answers
# every read the host lacks: non-zero, silent.
(
  SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
  source skills/ship/scripts/_lib.sh
  source skills/ship/scripts/host/ado.sh
  out=$(host_workflow_runs review.yml 2026-09-17T11:58:00Z 2>&1); rc=$?
  check_rc "the ADO adapter answers the new read non-zero" 1 "$rc"
  check "the ADO adapter says nothing" "" "$out"
  finish
) || _failed=1

finish
