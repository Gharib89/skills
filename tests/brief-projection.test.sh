#!/usr/bin/env bash
# ship_brief: the projection `poll-pr --brief` prints instead of the full shape.
# A pure transformation of the JSON the poll already built, so the cases here are
# strings in and strings out and nothing reaches a host. The expected values are
# built with their own `jq -cn` rather than by re-running the projection, so a
# case can disagree with it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

rep() { printf "%${1}s" '' | tr ' ' "$2"; }

round='{"id":11,"login":"copilot-pull-request-reviewer[bot]","state":"comment","substantive":true,
        "submitted_at":"2026-09-14T03:00:00Z",
        "body":"Reviewed 4 files and found 2 comments.\n\n- merge.sh:40 misses the none case\n- poll-pr.sh:9 stale usage line\n\nThanks!"}'
mine='{"id":12,"login":"Gharib89","state":"comment","substantive":true,
       "submitted_at":"2026-09-14T03:05:00Z","body":"fixed in abc1234"}'
older='{"id":9,"login":"copilot-pull-request-reviewer[bot]","state":"comment","substantive":true,
        "submitted_at":"2026-09-14T02:00:00Z","body":"- first round finding"}'

poll=$(jq -cn --argjson r "$round" --argjson m "$mine" --argjson o "$older" '
  {head_sha: "abc1234", mergeable: "clean",
   checks: [{name: "gate", status: "success"}],
   reviews: {on_head: [$r, $m], all: [$o, $r, $m], total: 3},
   threads: [{id: "t1", resolved: false, replied: false, author: "Copilot",
              path: "skills/ship/scripts/merge.sh", body: "nit: name the base"},
             {id: "t2", resolved: true, replied: true, author: "Copilot",
              path: "skills/ship/scripts/poll-pr.sh", body: "done"}],
   reviewer_blocked: null, landed_by: "head", done: true, waited_s: 20}')

# The lead line is the round's verdict and the items are what to fix; the prose
# between and after them goes.
findings='Reviewed 4 files and found 2 comments.
- merge.sh:40 misses the none case
- poll-pr.sh:9 stale usage line'

# The head rule: the rounds are the ones on the current head, the run's own reply
# row drops out, and the round body comes down to its finding items.
check "the head rule projects on_head without the run's own row" \
  "$(jq -cn --arg f "$findings" '{head_sha: "abc1234", mergeable: "clean", landed_by: "head",
      rounds: [{id: 11, submitted_at: "2026-09-14T03:00:00Z", substantive: true, body: $f}],
      threads: [{id: "t1", resolved: false, replied: false}]}')" \
  "$(ship_brief "$poll" Gharib89 on_head)"

# The since rule reads every head, so the round that landed before the last push
# is in the list too.
check "the since rule projects all[]" \
  "$(jq -cn --arg f "$findings" '{head_sha: "abc1234", mergeable: "clean", landed_by: "head",
      rounds: [{id: 9, submitted_at: "2026-09-14T02:00:00Z", substantive: true, body: "- first round finding"},
               {id: 11, submitted_at: "2026-09-14T03:00:00Z", substantive: true, body: $f}],
      threads: [{id: "t1", resolved: false, replied: false}]}')" \
  "$(ship_brief "$poll" Gharib89 all)"

# An identity that matches no row drops nothing: the exclusion is the run's own
# login, never a guess at which rows look like replies.
check "another identity drops no row" 2 \
  "$(ship_brief "$poll" someone-else on_head | jq '.rounds | length')"

# An identity the host could not name drops nothing: losing the rounds the poll
# came for is a worse answer than showing one row of our own.
check "an unreadable identity drops no row" 2 \
  "$(ship_brief "$poll" "" on_head | jq '.rounds | length')"

# A round with no finding items still has to be readable, so it is clipped the
# way the adapters clip a long body.
prose=$(rep 240 p)
clipped=$(jq -cn --argjson r "$round" --arg b "$prose" '
  {head_sha: "abc1234", mergeable: "clean", landed_by: null,
   reviews: {on_head: [$r + {body: $b}], all: [], total: 1}, threads: []}')
check "a round with no items is clipped, not emptied" \
  "$(printf '%s\n...[truncated]' "$(rep 200 p)")" \
  "$(ship_brief "$clipped" Gharib89 on_head | jq -r '.rounds[0].body')"

# `threads` is the string "unavailable" when the host refused the state; the
# projection reports that rather than an empty list, which would read as "no
# threads left to answer".
unreadable=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [], all: [], total: 0}, threads: "unavailable"}')
check "unreadable thread state passes through as the string" \
  '"unavailable"' "$(ship_brief "$unreadable" Gharib89 on_head | jq -c '.threads')"

finish
