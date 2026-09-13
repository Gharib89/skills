#!/usr/bin/env bash
# SHIP_REVIEW_CLIP: the review-body clip both host adapters run, and the ids
# `poll-pr --full` exempts from it. A pure jq transformation over strings; no
# call in this file reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

# rep <n> <char>: the expected values are built here rather than by slicing the
# input the way the transformation does, so a case can disagree with it.
rep() { printf "%${1}s" '' | tr ' ' "$2"; }

# clip <id-json> <body> <full-ids-json>: the adapters' call, in isolation.
clip() { jq -rn --argjson id "$1" --arg b "$2" --argjson full "$3" "$SHIP_REVIEW_CLIP"' $b | clip($id)'; }

preamble=$(rep 2000 p)
round="${preamble}FINDING"
marker=$'\n...[truncated]'

check "a body under the cap is untouched" \
  "short round" "$(clip 7 "short round" '[]')"

check "a body exactly at the cap is untouched" \
  "$preamble" "$(clip 7 "$preamble" '[]')"

check "a body past the cap is clipped and marked" \
  "${preamble}${marker}" "$(clip 7 "$round" '[]')"

check "an id --full names keeps its whole body, unmarked" \
  "$round" "$(clip 7 "$round" '["7"]')"

check "--full naming another id leaves this one clipped" \
  "${preamble}${marker}" "$(clip 7 "$round" '["8","9"]')"

check "a row with no id (an ADO vote) is clipped, not matched" \
  "${preamble}${marker}" "$(clip null "$round" '["7"]')"

finish
