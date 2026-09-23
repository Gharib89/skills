#!/usr/bin/env bash
# request-review over the real GitHub adapter: a request that landed reads back
# as one. `host_pr_request_review` takes it as landed when the timeline gained a
# `review_requested` event during the call, or when the reviewer is on the
# pending list under its login less a `[bot]` suffix or under its recorded
# alias; the timeline's own logins, which keep every earlier request, do not count.
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
mkdir -p "$repo" "$bin" "$FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git

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
req()   { ( cd "$repo" && bash "$mech" 7 "$1" 2>/dev/null ); }
posts() { grep -c -- '-X POST' "$FAKE/calls"; }

# The field case: the POST succeeds, the timeline has not surfaced the event,
# and the readback names the reviewer under the name GitHub records it as.
reset 'Copilot'
out=$(req 'copilot-pull-request-reviewer[bot]'); rc=$?
check_rc "a Copilot request read back as Copilot is requested" 0 "$rc"
check    "and reports requested: true" true "$(jq -r .requested <<<"$out")"
check    "and spends one POST, no retry" 1 "$(posts)"

# The alias belongs to Copilot's login: another reviewer is not read back by it.
reset 'Copilot'
out=$(req 'someone-else[bot]'); rc=$?
check_rc "Copilot on the readback does not read back another reviewer" 1 "$rc"

# The same-name app reviewer the `[bot]` bridge was written for still matches.
reset 'github-actions'
out=$(req 'github-actions[bot]'); rc=$?
check_rc "github-actions[bot] read back as github-actions is requested" 0 "$rc"
check    "and reports requested: true" true "$(jq -r .requested <<<"$out")"

# A timeline that gained the event is the other signal, and its time is the stamp.
reset '' 2 '{"login":"Copilot","created_at":"2026-09-21T15:00:00Z"}'
out=$(req 'copilot-pull-request-reviewer[bot]'); rc=$?
check_rc "a timeline delta alone is a landed request" 0 "$rc"
check    "and stamps requested_at from the event" 2026-09-21T15:00:00Z "$(jq -r .requested_at <<<"$out")"

# A reviewer requested before on this PR: its event is in the timeline before
# and after the call, the POST queues nothing, and nothing is pending. The
# earlier request must not read this one back.
prior='{"login":"Copilot","created_at":"2026-09-21T14:00:00Z"}'
reset '' 1 "$prior"
out=$(req 'copilot-pull-request-reviewer[bot]'); rc=$?
check_rc "an earlier request on the timeline does not read back a new one" 1 "$rc"
check    "and reports requested: false" false "$(jq -r .requested <<<"$out")"

# Neither signal: never-queued, after the one retry.
reset ''
out=$(req 'copilot-pull-request-reviewer[bot]'); rc=$?
check_rc "a request with no delta and no readback is not requested" 1 "$rc"
check    "and reports requested: false" false "$(jq -r .requested <<<"$out")"
check    "after exactly one retry POST" 2 "$(posts)"

finish
