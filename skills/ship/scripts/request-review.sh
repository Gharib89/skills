#!/usr/bin/env bash
# One on-request round: request the reviewer, then read the request back off
# the host's own record (an empty requested-reviewers list proves nothing, and
# the login requested and the login recorded can differ).
#
#   request-review <pr> <login>
#
# `requested_at` is the ISO-8601 time of the review_requested event the
# read-back found, or the wall clock where the host records no event time.
# Phase 7 passes it to `poll-pr --since` so the round counts on whatever head
# it lands on.
#
# stdout: {pr, login, requested, readback[], requested_at}
# exit: 0 requested and read back · 1 not read back (never-queued after one retry) · 2 usage
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: request-review <pr> <login>'
[ -n "${1:-}" ] && [ -n "${2:-}" ] || ship_tooling "$usage"
pr=$1; login=$2
[ $# -eq 2 ] || ship_tooling "unknown flag: $3"
ship_load_host
out=$(host_pr_request_review "$pr" "$login") || ship_tooling "request call failed"
first_at=$(jq -r '.requested_at // empty' <<<"$out")
if [ "$(jq -r .requested <<<"$out")" != true ]; then
  sleep 5
  out=$(host_pr_request_review "$pr" "$login") || ship_tooling "request call failed"
  # Keep the EARLIER stamp. The first POST may have landed with only its
  # read-back delayed, in which case the retry sees its own event in `before`
  # and falls back to a wall clock later than the request that actually
  # queued. Reporting the later one would make --since wait out a round that
  # arrived in between.
  out=$(jq --arg f "$first_at" '.requested_at = (
          [.requested_at, (if $f == "" then empty else $f end)] | min)' <<<"$out")
fi
jq --argjson pr "$pr" --arg l "$login" '{pr: $pr, login: $l} + .' <<<"$out"
[ "$(jq -r .requested <<<"$out")" = true ]
