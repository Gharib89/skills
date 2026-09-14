#!/usr/bin/env bash
# ship_stale_base_reason: the refusal `merge` reads off a `base-fresh` verdict
# before it squashes. A pure string-in, string-out decision; the live path, a
# scratch PR whose base has moved, is the `github-mechanics` verification's job.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

fresh='{"fresh":true,"base":"origin/main","behind":0,"ahead":2,"fetched":true}'
behind='{"fresh":false,"base":"origin/main","behind":3,"ahead":2,"fetched":true}'

check "a fresh verdict admits the merge" "" "$(ship_stale_base_reason "$fresh")"

check "a behind verdict refuses with the count and the base" \
  "stale-base: behind 3 on origin/main" "$(ship_stale_base_reason "$behind")"

# `merge` turns base-fresh's own exit 2 into tooling before this function sees
# the output. These two cases are what is left: an exit 0 or 1 whose payload
# still cannot be read. A check that could not ask its question must not answer
# "fresh", so the refusal stands.
check "an error verdict refuses rather than admits" \
  "stale-base: base freshness unreadable" \
  "$(ship_stale_base_reason '{"error":"cannot resolve origin/HEAD"}')"

check "output that is not JSON refuses" \
  "stale-base: base freshness unreadable" "$(ship_stale_base_reason 'bash: git: not found')"

check "no output at all refuses" \
  "stale-base: base freshness unreadable" "$(ship_stale_base_reason '')"

finish
