#!/usr/bin/env bash
# poll-pr --await-run: the window a comment-transport reviewer's workflow run
# opens. A run of that workflow is attached to the default branch's SHA, so the
# PR head's checks cannot see it, and a window that closed before the round
# landed was indistinguishable from a reviewer that never queued (#203).
#
# Driven end to end against a fake `gh` and a throwaway repo whose origin names
# GitHub, so the mechanic's own loop is the subject: no case reaches a host.
# The fake ignores every `--jq` filter and answers with the shape that filter
# produces, one fixture per call in sequence, the last one repeating.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/poll-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
bin=$work/bin; repo=$work/repo; export FAKE=$work/fake
mkdir -p "$bin" "$repo" "$FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git

cat > "$bin/gh" <<'FAKE'
#!/usr/bin/env bash
# Counters and fixtures live under $FAKE: <kind>.<n>.json is the answer to the
# n-th call of that kind, and a sequence that runs out repeats its last entry.
inc() {
  local n; n=$(cat "$FAKE/$1.n" 2>/dev/null || echo 0); n=$((n + 1))
  printf '%s' "$n" > "$FAKE/$1.n"; printf '%s' "$n"
}
pick() {
  local kind=$1 n f; n=$(inc "$kind")
  while [ "$n" -gt 0 ]; do
    f="$FAKE/$kind.$n.json"; [ -f "$f" ] && { cat "$f"; return 0; }
    n=$((n - 1))
  done
}
[ "${1:-}" = run ] && { pick runs; exit 0; }
path=$2; [ "$2" = -i ] && { path=$3; printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n'; }
case $path in
  graphql) printf '{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}\n'; exit 0 ;;
  */pulls/[0-9]*/reviews)
    # Two reads share this path: the rounds (filter `.[]`) and the blocked
    # notice (filter naming submitted_at), which every case here leaves empty.
    case $* in *submitted_at*) ;; *) pick reviews ;; esac ;;
  */pulls/[0-9]*) cat "$FAKE/pr.json" ;;
esac
exit 0
FAKE
chmod +x "$bin/gh"
PATH=$bin:$PATH

title='fix(ship): the PR under review'
cat > "$FAKE/pr.json" <<EOF
{"number":7,"url":"https://example.invalid/7","title":"$title","body":"",
 "head_sha":"deadbee","head_ref":"fix/x-7","base_ref":"main","state":"open","mergeable":"clean"}
EOF
round='{"id":1,"user":{"login":"claude[bot]"},"state":"COMMENTED","body":"- a finding",
        "submitted_at":"2026-09-17T12:00:00Z","commit_id":"deadbee"}'
run_row() { # <status> <conclusion> [<title>]
  jq -cn --arg s "$1" --arg c "$2" --arg t "${3:-$title}" \
    '[{status: $s, conclusion: (if $c == "" then null else $c end),
       created_at: "2026-09-17T11:59:00Z", url: "https://example.invalid/runs/9", title: $t}]'
}

reset() { rm -f "$FAKE"/*.n "$FAKE"/runs.*.json "$FAKE"/reviews.*.json; }
poll() { ( cd "$repo" && bash "$mech" 7 --await-review 'claude[bot]' --since 2026-09-17T11:58:00Z \
  --timeout 0 --interval 1 "$@" ); }
calls() { cat "$FAKE/$1.n" 2>/dev/null || echo 0; }

# A run still going at the window's end is the case the bug was: the round was
# 2 to 3 minutes out, the window closed, and the run reported the reviewer
# silent. The window now runs to the run's conclusion.
reset
run_row in_progress ''      > "$FAKE/runs.1.json"
run_row completed success   > "$FAKE/runs.2.json"
printf ''                   > "$FAKE/reviews.1.json"
printf '%s\n' "$round"      > "$FAKE/reviews.2.json"
out=$(poll --await-run claude-review.yml); rc=$?
check_rc "an in_progress run keeps the poll going until the round lands" 0 "$rc"
check "the round that landed past the window is the round" \
  'true since completed' \
  "$(jq -r '[(.done|tostring), .landed_by, .reviewer_run.status] | join(" ")' <<<"$out")"

# The same fixtures without the flag: the window closes on the second the
# timeout names, which is the behaviour this flag exists to fix.
reset
run_row in_progress ''      > "$FAKE/runs.1.json"
printf ''                   > "$FAKE/reviews.1.json"
printf '%s\n' "$round"      > "$FAKE/reviews.2.json"
out=$(poll); rc=$?
check_rc "without --await-run the window still closes at --timeout" 1 "$rc"
check "and the run is not read at all" 'false null' \
  "$(jq -r '[(.done|tostring), (.reviewer_run|tostring)] | join(" ")' <<<"$out")"

# A concluded run buys one more interval for the review row to appear, and one
# only: waiting longer on a run that is over is waiting on nothing.
reset
run_row completed success > "$FAKE/runs.1.json"
printf ''                 > "$FAKE/reviews.1.json"
out=$(poll --await-run claude-review.yml); rc=$?
check_rc "a concluded run with no row yet closes the window after one more poll" 1 "$rc"
check "the extra poll is one" 2 "$(calls reviews)"
check "and the run is on the record" 'false completed success' \
  "$(jq -r '[(.done|tostring), .reviewer_run.status, .reviewer_run.conclusion] | join(" ")' <<<"$out")"

# A failed run is the reviewer's infrastructure, not its silence: the URL is
# what sends the human to the failure.
reset
run_row completed failure > "$FAKE/runs.1.json"
printf ''                 > "$FAKE/reviews.1.json"
out=$(poll --await-run claude-review.yml); rc=$?
check_rc "a failed run closes the window" 1 "$rc"
check "the failure comes back with the run URL" \
  'completed failure https://example.invalid/runs/9' \
  "$(jq -r '[.reviewer_run.status, .reviewer_run.conclusion, .reviewer_run.url] | join(" ")' <<<"$out")"
check "a failed run buys no extra poll" 1 "$(calls reviews)"

# No run at all: the status the review loop reads as never-queued.
reset
printf '[]\n'             > "$FAKE/runs.1.json"
printf ''                 > "$FAKE/reviews.1.json"
out=$(poll --await-run claude-review.yml)
check "no run since the request reports the none status" 'none null' \
  "$(jq -r '[.reviewer_run.status, (.reviewer_run.conclusion|tostring)] | join(" ")' <<<"$out")"

# The workflow fires on every comment in the repo, so a run belonging to another
# PR is not this reviewer's round and must not hold the window open.
reset
run_row in_progress '' 'another PR entirely' > "$FAKE/runs.1.json"
printf ''                                    > "$FAKE/reviews.1.json"
out=$(poll --await-run claude-review.yml)
check "a run for another PR is not this PR's round" 'none' \
  "$(jq -r '.reviewer_run.status' <<<"$out")"
check "and it holds the window open for nothing" 1 "$(calls reviews)"

# The workflow's own `if` answers a comment that was not the request with a
# skipped run, and that run says nothing about the round: the run that did
# something is the one the poll reports, however new the skipped one is.
reset
jq -cn --arg t "$title" '[{status: "completed", conclusion: "success",
     created_at: "2026-09-17T11:59:00Z", url: "https://example.invalid/runs/9", title: $t},
    {status: "completed", conclusion: "skipped",
     created_at: "2026-09-17T11:59:30Z", url: "https://example.invalid/runs/10", title: $t}]' \
  > "$FAKE/runs.1.json"
printf '' > "$FAKE/reviews.1.json"
out=$(poll --await-run claude-review.yml)
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
  > "$FAKE/runs.1.json"
printf ''               > "$FAKE/reviews.1.json"
printf '%s\n' "$round" > "$FAKE/reviews.2.json"
out=$(poll --await-run claude-review.yml); rc=$?
check_rc "a live run outranks a newer concluded one and holds the window" 0 "$rc"
check "and it is the run reported" 'in_progress https://example.invalid/runs/9' \
  "$(jq -r '[.reviewer_run.status, .reviewer_run.url] | join(" ")' <<<"$out")"

# --await-run has no meaning without the reviewer it belongs to, or without the
# instant the request happened.
err() { ( cd "$repo" && bash "$mech" "$@" 2>/dev/null | jq -r '.error' ); }
check "--await-run alone is a usage error" '--await-run needs --await-review and --since' \
  "$(err 7 --await-run claude-review.yml)"
check "--await-run without --since is a usage error" '--await-run needs --await-review and --since' \
  "$(err 7 --await-review 'claude[bot]' --await-run claude-review.yml)"

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
