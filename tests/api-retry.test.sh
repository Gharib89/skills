#!/usr/bin/env bash
# api(): the GitHub adapter's REST wrapper. Two claims, both proved against the
# fake `gh` in tests/gh-fake.sh so no case reaches a host: its retry resends the
# request the first attempt sent, the stdin payload included (#108), and its
# retry POLICY reads the HTTP status, so a 5xx or 429 burst gets the bounded
# backoff a host outage needs while every other failure keeps the single retry
# the 401 flake it was written for needs (#173).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/gh-fake.sh
# The adapter reads these at source time; no call in this file reaches a host.
SHIP_OWNER=owner SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh

# The wrapper waits between attempts. The wait lengths are not under test, the
# attempt count is, so a no-op shadows every sleep.
sleep() { :; }

bin=$(mktemp -d); trap 'rm -rf "$bin"' EXIT
gh_fake_install "$bin"

payload='{"body":"a line\nand another"}'

# #108: the first attempt drains the pipe, so a retry that re-runs the same
# argument list sends nothing and GitHub answers "Body should be a JSON object".
gh_reset; export GH_STATUS_SEQ="500 200"
out=$(printf '%s' "$payload" | api -X PATCH "$R/pulls/1" --input -); rc=$?
check_rc "reports success once the retry lands"        0 "$rc"
check    "retries a failed stdin-fed call"             2 "$(gh_attempts)"
check    "sends the payload on the first attempt"      "$payload" "$(gh_body_of 1)"
check    "resends the same payload on the retry"       "$payload" "$(gh_body_of 2)"
check    "strips the header block from the answer"     "ok" "$out"

# A call with no stdin payload keeps its current behaviour: it is retried, and
# nothing tries to read a pipe that was never there.
gh_reset; export GH_STATUS_SEQ="500 200"
api user --jq .login >/dev/null; rc=$?
check_rc "reports success for a retried read"          0 "$rc"
check    "retries a read"                              2 "$(gh_attempts)"

# `gh` takes the flag glued to its value too, so the guard reads both spellings
# and a `--input=-` call is buffered like any other.
gh_reset; export GH_STATUS_SEQ="500 200"
printf '%s' "$payload" | api -X PATCH "$R/pulls/1" --input=- >/dev/null; rc=$?
check_rc "reports success for a glued-flag retry"      0 "$rc"
check    "resends the payload of a glued-flag call"    "$payload" "$(gh_body_of 2)"

# A first attempt that succeeds is the only attempt: the buffering must not
# turn one request into two.
gh_reset; export GH_STATUS_SEQ="200"
printf '%s' "$payload" | api -X PATCH "$R/pulls/1" --input - >/dev/null; rc=$?
check_rc "reports success for a first-attempt success" 0 "$rc"
check    "does not resend a request that succeeded"    1 "$(gh_attempts)"
check    "sends the payload once"                      "$payload" "$(gh_body_of 1)"

# 429 is the other status the host answers with when the payload is fine.
gh_reset; export GH_STATUS_SEQ="429 200"
api user >/dev/null; rc=$?
check_rc "a 429 that clears is a success"              0 "$rc"
check    "retries a 429"                               2 "$(gh_attempts)"

# PR #170: minutes of 500s. The backoff is bounded, so a host that stays down
# still fails, after five attempts rather than after two.
gh_reset; export GH_STATUS_SEQ="500"
api user >/dev/null; rc=$?
check_rc "a 500 burst fails once the backoff is spent" 1 "$rc"
check    "bounds the 5xx backoff at five attempts"     5 "$(gh_attempts)"

# A 4xx is the payload, not the host: one more attempt for the 401 flake, and
# no backoff beyond it.
gh_reset; export GH_STATUS_SEQ="400"
api user >/dev/null; rc=$?
check_rc "a 400 that repeats fails"                    1 "$rc"
check    "does not back off a 400"                     2 "$(gh_attempts)"

gh_reset; export GH_STATUS_SEQ="401 200"
api user >/dev/null; rc=$?
check_rc "the 401 flake still clears on its retry"     0 "$rc"
check    "retries a 401 once"                          2 "$(gh_attempts)"

# A POST can be a write that landed with its response lost on the way back, so
# it keeps the one retry it had before the backoff arrived, whatever the status.
gh_reset; export GH_STATUS_SEQ="500"
api -X POST "$R/issues/1/comments" >/dev/null; rc=$?
check_rc "a POST against a 500 burst fails"            1 "$rc"
check    "does not back off a POST"                    2 "$(gh_attempts)"

# The status is read by the same rule that strips the headers, so an error body
# ending in a status-shaped line cannot pass itself off as the real status and
# turn one retry into five.
gh_reset; export GH_STATUS_SEQ="404"
export GH_BODY=$'{"message":"Not Found"}\nHTTP/1.1 500 Internal Server Error'
api user >/dev/null; rc=$?
check_rc "a 404 carrying a status-shaped body fails"   1 "$rc"
check    "reads the status off the headers, not the body" 2 "$(gh_attempts)"
unset GH_BODY

# `--paginate` answers with one header block per page, the second introduced by
# a blank line. The pages have to concatenate exactly as they do without `-i`,
# so that separator goes out with the block and nothing else moves.
gh_reset; export GH_STATUS_SEQ="200"
export GH_BODY=$'{"a":1}\n\nHTTP/2.0 200 OK\nContent-Type: application/json\n\n{"b":2}'
check "concatenates the pages of a paginated answer" \
  "$(printf '{"a":1}\n{"b":2}')" "$(api 'repos/o/r/issues' --paginate --jq '.[]')"

# A body line shaped like a status line, mid-page, is body: a header block only
# ever starts the response or follows the blank line that ended the page before.
gh_reset
export GH_BODY=$'{"a":1}\nHTTP/1.1 200 OK\n{"b":2}'
check "a status-shaped body line survives mid-page" \
  "$(printf '{"a":1}\nHTTP/1.1 200 OK\n{"b":2}')" "$(api 'repos/o/r/issues' --jq '.[]')"

# A blank line inside one page's body is the body's own, and stays.
gh_reset
export GH_BODY=$'{"a":1}\n\n{"b":2}'
check "a blank line inside a page survives" \
  "$(printf '{"a":1}\n\n{"b":2}')" "$(api 'repos/o/r/issues' --jq '.[]')"
unset GH_BODY

# No HTTP answer at all (the tool missing, a refused connection): there is no
# status to classify on, so it takes the single retry, not the backoff.
gh_reset; export GH_STATUS_SEQ="none"
api user >/dev/null; rc=$?
check_rc "a call with no HTTP answer fails"            1 "$rc"
check    "does not back off without a status"          2 "$(gh_attempts)"

finish
