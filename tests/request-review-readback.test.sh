#!/usr/bin/env bash
# request-review over the real GitHub adapter: a request that landed reads back
# as one. `host_pr_request_review` takes it as landed when the timeline gained a
# `review_requested` event for the reviewer during the call, or when the reviewer is on the
# pending list under its login less a `[bot]` suffix or under its recorded
# alias; the logins of earlier requests the reviewer answered or that were
# withdrawn, which the timeline keeps, do not count. A round already in flight
# does: before the call, the reviewer's last review event on the timeline was a
# request it had not answered, which is how a Copilot ruleset's PR-open round
# reads while Copilot is mid-review and off the pending list (#444).
# The pending list alone must suffice, because the timeline can lag the adapter's
# wait; Copilot, requested as copilot-pull-request-reviewer[bot] and recorded
# as `Copilot`, is the alias case (#239).
#
# Driven end to end in a throwaway checkout whose origin names GitHub, with a
# fake `gh` in front of PATH answering per call: the timeline from a fixture per
# read in sequence, the last repeating, and the PR read from one readback
# fixture. A no-op `sleep` beside it keeps the adapter's and the mechanic's
# waits out of the run. No case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/request-review.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo bin=$work/bin
export FAKE=$work/fake
mkdir -p "$repo/docs/agents" "$bin" "$FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
# The mechanic takes a reviewer by its `### <name>` block, so the fixture
# profile names one per login a case requests, all on the host's request call.
block() { printf '### %s\n\nLogin: %s\nTrigger: on-request\nRequest: None.\nWorkflow: None.\nCap: 3\nGating: no\nFallback-for: None.\n\n' "$1" "$2"; }
{ printf '## Reviewers\n\n'
  block copilot 'copilot-pull-request-reviewer[bot]'
  block actions 'github-actions[bot]'
  block other 'someone-else[bot]'
  printf '## Coding standards\n'
} > "$repo/docs/agents/ship.md"

cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
# `gh api -i <args>`: log the call, answer with a header block and the body the
# call's own `--jq` would have printed.
printf '%s\n' "$*" >> "$FAKE/calls"
case " $* " in
  *" POST "*/requested_reviewers*) body='{}' ;;
  */timeline*)
    n=$(( $(cat "$FAKE/timeline.n" 2>/dev/null || echo 0) + 1 ))
    printf '%s' "$n" > "$FAKE/timeline.n"
    f=$FAKE/timeline.$n
    while [ ! -f "$f" ] && [ "$n" -gt 1 ]; do n=$((n - 1)); f=$FAKE/timeline.$n; done
    body=$(cat "$f") ;;
  */pulls/7*) body=$(cat "$FAKE/readback") ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n'
[ -n "$body" ] && printf '%s\n' "$body"
exit 0
GH
printf '#!/bin/sh\nexit 0\n' > "$bin/sleep"
chmod +x "$bin/gh" "$bin/sleep"
export PATH=$bin:$PATH

reset() { # <readback-logins, one per line> [<timeline read n> <event lines>]...
  rm -f "$FAKE"/*
  : > "$FAKE/calls"
  printf '%s' "$1" > "$FAKE/readback"; shift
  : > "$FAKE/timeline.1"
  while [ $# -gt 1 ]; do printf '%s' "$2" > "$FAKE/timeline.$1"; shift 2; done
}
req()   { ( cd "$repo" && bash "$mech" 7 --reviewer "$1" 2>/dev/null ); }
posts() { grep -c -- '-X POST' "$FAKE/calls"; }

# The field case: the POST succeeds, the timeline has not surfaced the event,
# and the readback names the reviewer under the name GitHub records it as.
reset 'Copilot'
out=$(req copilot); rc=$?
check_rc "a Copilot request read back as Copilot is requested" 0 "$rc"
check    "and reports requested: true" true "$(jq -r .requested <<<"$out")"
check    "and spends one POST, no retry" 1 "$(posts)"

# The alias belongs to Copilot's login: another reviewer is not read back by it.
reset 'Copilot'
out=$(req other); rc=$?
check_rc "Copilot on the readback does not read back another reviewer" 1 "$rc"

# The same-name app reviewer the `[bot]` bridge was written for still matches.
reset 'github-actions'
out=$(req actions); rc=$?
check_rc "github-actions[bot] read back as github-actions is requested" 0 "$rc"
check    "and reports requested: true" true "$(jq -r .requested <<<"$out")"

# A timeline that gained the event is the other signal, and its time is the stamp.
reset '' 2 '{"event":"review_requested","login":"Copilot","created_at":"2026-09-21T15:00:00Z"}'
out=$(req copilot); rc=$?
check_rc "a timeline delta alone is a landed request" 0 "$rc"
check    "and stamps requested_at from the event" 2026-09-21T15:00:00Z "$(jq -r .requested_at <<<"$out")"

# Another reviewer is requested during the call: the timeline gains its event,
# not this reviewer's, and nothing is pending. That event must not read this
# request back, nor lend it its time (#451).
reset '' 2 '{"event":"review_requested","login":"someone-else","created_at":"2026-09-21T15:00:00Z"}'
out=$(req copilot); rc=$?
check_rc "another reviewer's event during the call does not read back this one" 1 "$rc"
check    "and reports requested: false" false "$(jq -r .requested <<<"$out")"
check    "nor takes that event's time" false "$(jq -r '.requested_at == "2026-09-21T15:00:00Z"' <<<"$out")"

# A reviewer requested and answered before on this PR: its events are in the
# timeline before and after the call, the POST queues nothing, and nothing is
# pending. The earlier round must not read this one back.
prior='{"event":"review_requested","login":"Copilot","created_at":"2026-09-21T14:00:00Z"}'
answered='{"event":"reviewed","login":"Copilot","created_at":"2026-09-21T14:03:00Z"}'
reset '' 1 "$prior
$answered"
out=$(req copilot); rc=$?
check_rc "an earlier answered request does not read back a new one" 1 "$rc"
check    "and reports requested: false" false "$(jq -r .requested <<<"$out")"

# A request withdrawn before it was answered queues nothing either.
reset '' 1 "$prior
{\"event\":\"review_request_removed\",\"login\":\"Copilot\",\"created_at\":\"2026-09-21T14:01:00Z\"}"
out=$(req copilot); rc=$?
check_rc "a withdrawn request does not read back a new one" 1 "$rc"

# The field case of #444: a ruleset requested Copilot at PR open, Copilot is
# mid-review so it is off the pending list, and the re-request writes no event.
# That round is in flight: the request reads as landed, stamped at the ruleset's
# event, so a poll --since it catches the round.
reset '' 1 "$prior"
out=$(req copilot); rc=$?
check_rc "an unanswered request on the timeline is a round in flight" 0 "$rc"
check    "and stamps requested_at from that request" 2026-09-21T14:00:00Z "$(jq -r .requested_at <<<"$out")"
check    "on the one POST" 1 "$(posts)"

# A reviewer still pending from an earlier request: GitHub no-ops the POST and
# writes no event, but the round it owes is queued and unposted, so it lands
# after this call and the request reads as landed.
reset 'Copilot' 1 "$prior"
out=$(req copilot); rc=$?
check_rc "a reviewer already pending reads back as requested" 0 "$rc"
check    "on the one POST" 1 "$(posts)"

# That round's review lands during the call: it was in flight when the call
# began, so it still reads as landed, stamped at its request.
reset '' 1 "$prior" 2 "$prior
$answered"
out=$(req copilot); rc=$?
check_rc "a round answered during the call still reads as landed" 0 "$rc"
check    "and keeps its request's stamp" 2026-09-21T14:00:00Z "$(jq -r .requested_at <<<"$out")"

# Withdrawn during the call instead: nothing is in flight any more.
reset '' 1 "$prior" 2 "$prior
{\"event\":\"review_request_removed\",\"login\":\"Copilot\",\"created_at\":\"2026-09-21T14:01:00Z\"}"
out=$(req copilot); rc=$?
check_rc "a round withdrawn during the call does not read as landed" 1 "$rc"

# Neither signal: never-queued, after the one retry.
reset ''
out=$(req copilot); rc=$?
check_rc "a request with no delta and no readback is not requested" 1 "$rc"
check    "and reports requested: false" false "$(jq -r .requested <<<"$out")"
check    "after exactly one retry POST" 2 "$(posts)"

finish
