#!/usr/bin/env bash
# Which check run `ci-wait` and `poll-pr` answer for (#394). Two ways a read
# graded the wrong run:
#
# - A workflow whose concurrency group cancels a superseded run leaves that
#   run's `cancelled` check on the head, and its successor can have no check run
#   yet. The GitHub `host_pr_checks` read the cancelled row as the leg failing.
#   Within a name the latest row is now the latest by check-run id, and a
#   cancelled row whose workflow has a newer run on the head reads `pending`.
# - Straight after a push the host can still show the previous head. Both
#   mechanics now wait for the expected head: `--sha`, else the local HEAD of a
#   checkout of the PR's head branch.
#
# A fake `gh` in front of PATH answers per endpoint from raw fixtures and applies
# the call's own `--jq`, so the adapter's projections are what is under test. No
# case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
root=$PWD

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
bin=$work/bin
export FAKE=$work/fake
mkdir -p "$bin" "$FAKE"

cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
# `gh api [-i] <path> ... [--jq <expr>]`: log the path, answer from a fixture per
# endpoint, and apply the call's own --jq the way gh does.
jqx="." prev="" include="" path=""
for a in "$@"; do
  case $prev in --jq) jqx=$a ;; esac
  case $a in
    -i) include=1 ;;
    graphql) path=graphql ;;
    repos/*) [ -z "$path" ] && path=$a ;;
  esac
  prev=$a
done
printf '%s\n' "$path" >> "$FAKE/calls"
answer() { # <raw-json>
  [ -n "$include" ] && printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n'
  jq -rc "$jqx" <<<"$1"; exit 0
}
case $path in
  # The first `old-polls` reads of the PR show `old-sha`, every later one `new-sha`.
  */pulls/1)
    n=$(( $(cat "$FAKE/pulls.n" 2>/dev/null || echo 0) + 1 )); printf '%s' "$n" > "$FAKE/pulls.n"
    sha=$(cat "$FAKE/new-sha"); [ "$n" -gt "$(cat "$FAKE/old-polls")" ] || sha=$(cat "$FAKE/old-sha")
    answer "$(jq -n --arg s "$sha" '{number: 1, html_url: "u", title: "t", body: "",
      head: {sha: $s, ref: "fix/fake-1"}, base: {ref: "main"}, merged: false, state: "open",
      mergeable: true, mergeable_state: "clean"}')" ;;
  */pulls/1/reviews*) answer "$(cat "$FAKE/reviews.json")" ;;
  */commits/*/check-runs*)
    sha=${path#*/commits/}; sha=${sha%%/*}
    f=$FAKE/check-runs-$sha.json; [ -f "$f" ] || f=$FAKE/check-runs.json
    answer "$(cat "$f")" ;;
  */commits/*/status*) answer '{"statuses":[]}' ;;
  */actions/runs*) answer "$(cat "$FAKE/runs.json")" ;;
  graphql) answer '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}' ;;
esac
echo "fake gh: unexpected call: $*" >&2; exit 1
GH
chmod +x "$bin/gh"
export PATH=$bin:$PATH

run() { # <id> <name> <status> <conclusion|null> <started> <completed|null> <suite>
  jq -n --argjson id "$1" --arg n "$2" --arg s "$3" --argjson c "$4" --arg st "$5" \
    --argjson co "$6" --argjson su "$7" \
    '{id: $id, name: $n, status: $s, conclusion: $c, started_at: $st, completed_at: $co, check_suite: {id: $su}}'
}
runs_of() { jq -s '{total_count: length, check_runs: .}' > "$FAKE/check-runs.json"; }
workflows() { printf '%s' "$1" > "$FAKE/runs.json"; }
actions_reads() { grep -c '/actions/runs' "$FAKE/calls" 2>/dev/null; }
: > "$FAKE/calls"

# --- host_pr_checks ------------------------------------------------------------

(
  SHIP_OWNER=owner SHIP_REPO=repo
  source skills/ship/scripts/_lib.sh
  source skills/ship/scripts/host/github.sh
  checks() { host_pr_checks 1 abc | jq -c .; }

  # The #392 shape: a success, then a run the concurrency group cancelled when a
  # third run of the same workflow was queued, and that third run has no check
  # run yet. The cancelled row is not a result.
  { run 1 bump-guard completed '"success"' 2026-09-29T02:15:28Z '"2026-09-29T02:15:33Z"' 501
    run 2 bump-guard completed '"cancelled"' 2026-09-29T02:17:42Z '"2026-09-29T02:22:43Z"' 502
  } | runs_of
  workflows '{"workflow_runs":[{"id":10,"workflow_id":7,"check_suite_id":501},
    {"id":11,"workflow_id":7,"check_suite_id":502},{"id":12,"workflow_id":7,"check_suite_id":503}]}'
  check "a superseded cancelled run with no successor row reads pending" \
    '[{"name":"bump-guard","status":"pending"}]' "$(checks)"

  # The successor's own row reports, and it is the one read.
  { run 1 bump-guard completed '"success"' 2026-09-29T02:15:28Z '"2026-09-29T02:15:33Z"' 501
    run 2 bump-guard completed '"cancelled"' 2026-09-29T02:17:42Z '"2026-09-29T02:22:43Z"' 502
    run 3 bump-guard completed '"success"' 2026-09-29T02:22:45Z '"2026-09-29T02:22:51Z"' 503
  } | runs_of
  check "the successor's row reports for the name" \
    '[{"name":"bump-guard","status":"success"}]' "$(checks)"

  # A cancellation that completed after a newer row finished does not win on its
  # later time: the newer row is the newer by id. No workflow stands behind
  # either, so the id rule is the only one deciding.
  { run 2 lint completed '"cancelled"' 2026-09-29T02:17:42Z '"2026-09-29T02:22:43Z"' 601
    run 3 lint completed '"success"' 2026-09-29T02:20:00Z '"2026-09-29T02:21:00Z"' 602
  } | runs_of
  workflows '{"workflow_runs":[]}'
  check "the newest row by id wins over a later-completing cancellation" \
    '[{"name":"lint","status":"success"}]' "$(checks)"

  # A cancelled run with no newer run of its workflow was cancelled by a human:
  # the leg failed, now.
  run 2 bump-guard completed '"cancelled"' 2026-09-29T02:17:42Z '"2026-09-29T02:22:43Z"' 502 | runs_of
  workflows '{"workflow_runs":[{"id":11,"workflow_id":7,"check_suite_id":502}]}'
  check "a lone cancelled run reads failure" \
    '[{"name":"bump-guard","status":"failure"}]' "$(checks)"

  # A newer run of a different workflow supersedes nothing.
  workflows '{"workflow_runs":[{"id":11,"workflow_id":7,"check_suite_id":502},{"id":12,"workflow_id":8,"check_suite_id":503}]}'
  check "another workflow's newer run does not supersede" \
    '[{"name":"bump-guard","status":"failure"}]' "$(checks)"

  # The Actions read is paid only where a cancelled row needs it.
  : > "$FAKE/calls"
  run 1 bump-guard completed '"success"' 2026-09-29T02:15:28Z '"2026-09-29T02:15:33Z"' 501 | runs_of
  checks >/dev/null
  check "no cancelled row makes no Actions read" 0 "$(actions_reads)"
  finish
) || _failed=1

# --- ci-wait and poll-pr over the expected head --------------------------------

# A GitHub-origin checkout on the PR's head branch, whose profile expects no
# checks, so the no-checks grace is zero and a short --timeout is admitted.
co=$work/co; mkdir -p "$co/docs/agents"
printf '# Ship profile\n\nSchema: 3\n\n## CI\n\nLegs: None.\nNo-checks legal: yes, nothing here\nPush policy: Default.\n' \
  > "$co/docs/agents/ship.md"
git -C "$co" init -q -b fix/fake-1
git -C "$co" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
git -C "$co" remote add origin https://github.com/owner/repo.git
new=$(git -C "$co" rev-parse HEAD)
old=1111111111111111111111111111111111111111
printf '%s' "$new" > "$FAKE/new-sha"; printf '%s' "$old" > "$FAKE/old-sha"

# The old head's leg failed and the new head's passed, so an answer for the old
# head is visible as the wrong status as well as the wrong sha.
run 1 bump-guard completed '"failure"' 2026-09-29T02:15:28Z '"2026-09-29T02:15:33Z"' 501 \
  | jq -s '{total_count: 1, check_runs: .}' > "$FAKE/check-runs-$old.json"
run 2 bump-guard completed '"success"' 2026-09-29T02:16:28Z '"2026-09-29T02:16:33Z"' 502 | runs_of
workflows '{"workflow_runs":[]}'
jq -n --arg s "$old" '[{id: 9, user: {login: "rev"}, state: "COMMENTED", submitted_at: "2026-09-29T02:15:00Z",
  body: "a round on the old head", commit_id: $s}]' > "$FAKE/reviews.json"

polls() { rm -f "$FAKE/pulls.n"; printf '%s' "$1" > "$FAKE/old-polls"; }
ciwait() { ( cd "$1" && shift && bash "$root/skills/ship/scripts/ci-wait.sh" 1 "$@" 2>/dev/null ); }
pollpr() { ( cd "$1" && shift && bash "$root/skills/ship/scripts/poll-pr.sh" 1 "$@" 2>/dev/null ); }

polls 2
out=$(ciwait "$co" --timeout 30 --interval 0)
check "ci-wait waits out the old head and answers green" green "$(jq -r .status <<<"$out")"
check "and names the expected head" "$new" "$(jq -r .head_sha <<<"$out")"

polls 2
out=$(pollpr "$co" --timeout 30 --interval 0)
check "poll-pr answers for the expected head" "$new" "$(jq -r .head_sha <<<"$out")"
check "and counts no old-head review as on_head" 0 "$(jq '.reviews.on_head | length' <<<"$out")"

polls 100000
out=$(ciwait "$co" --timeout 2 --interval 1)
check "a head that never arrives is a timeout" timeout "$(jq -r .status <<<"$out")"
check "carrying the host's head" "$old" "$(jq -r .head_sha <<<"$out")"

# Off the PR's branch there is no expected head: the first read is the answer,
# as before.
git -C "$co" checkout -q -b elsewhere
polls 2
out=$(ciwait "$co" --timeout 30 --interval 0)
check "off the head branch the first read answers" "checks-failed $old" "$(jq -r '"\(.status) \(.head_sha)"' <<<"$out")"

# --sha names the expected head from anywhere.
polls 2
out=$(ciwait "$co" --sha "${new:0:12}" --timeout 30 --interval 0)
check "--sha waits for the head it names" "green $new" "$(jq -r '"\(.status) \(.head_sha)"' <<<"$out")"

# A lone cancelled leg on the expected head is checks-failed at once.
git -C "$co" checkout -q fix/fake-1
run 2 bump-guard completed '"cancelled"' 2026-09-29T02:16:28Z '"2026-09-29T02:16:33Z"' 502 | runs_of
workflows '{"workflow_runs":[{"id":11,"workflow_id":7,"check_suite_id":502}]}'
polls 0
out=$(ciwait "$co" --interval 30)
check "a lone cancelled leg is checks-failed" checks-failed "$(jq -r .status <<<"$out")"
check "without waiting out the window" true "$(jq '.waited_s < 30' <<<"$out")"

finish
