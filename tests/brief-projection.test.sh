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
   reviewer: {name: "copilot", login: "copilot-pull-request-reviewer[bot]", rule: "head",
              await_run: null, timeout: 600},
   reviewer_blocked: null, reviewer_run: {status: "completed", conclusion: "success",
                                          url: "https://example.invalid/runs/9"},
   landed_by: "head", done: true, waited_s: 20}')

# The lead line is the round's verdict and the items are what to fix; the prose
# between and after them goes.
findings='Reviewed 4 files and found 2 comments.
- merge.sh:40 misses the none case
- poll-pr.sh:9 stale usage line'

# The head rule: the rounds are the ones on the current head, the run's own reply
# row drops out, and the round body comes down to its finding items.
check "the head rule projects on_head without the run's own row" \
  "$(jq -cn --arg f "$findings" '{head_sha: "abc1234", mergeable: "clean",
      reviewer: {name: "copilot", login: "copilot-pull-request-reviewer[bot]", rule: "head",
                 await_run: null, timeout: 600},
      landed_by: "head", refused_by: null, reviewer_blocked: null,
      reviewer_run: {status: "completed", conclusion: "success", url: "https://example.invalid/runs/9"},
      rounds: [{id: 11, submitted_at: "2026-09-14T03:00:00Z", substantive: true, body: $f}],
      threads: [{id: "t1", path: "skills/ship/scripts/merge.sh", lead: "nit: name the base",
                 resolved: false, replied: false}]}')" \
  "$(ship_brief "$poll" Gharib89 on_head)"

# The since rule reads every head, so the round that landed before the last push
# is in the list too.
check "the since rule projects all[]" \
  "$(jq -cn --arg f "$findings" '{head_sha: "abc1234", mergeable: "clean",
      reviewer: {name: "copilot", login: "copilot-pull-request-reviewer[bot]", rule: "head",
                 await_run: null, timeout: 600},
      landed_by: "head", refused_by: null, reviewer_blocked: null,
      reviewer_run: {status: "completed", conclusion: "success", url: "https://example.invalid/runs/9"},
      rounds: [{id: 9, submitted_at: "2026-09-14T02:00:00Z", substantive: true, body: "- first round finding"},
               {id: 11, submitted_at: "2026-09-14T03:00:00Z", substantive: true, body: $f}],
      threads: [{id: "t1", path: "skills/ship/scripts/merge.sh", lead: "nit: name the base",
                 resolved: false, replied: false}]}')" \
  "$(ship_brief "$poll" Gharib89 all)"

# An identity that matches no row drops nothing: the exclusion is the run's own
# login, never a guess at which rows look like replies.
# The same poll with no reviewer awaited, so the identity is the only filter left
# and these cases read it alone.
unawaited=$(jq -c '.reviewer = null' <<<"$poll")
check "another identity drops no row" 2 \
  "$(ship_brief "$unawaited" someone-else on_head | jq '.rounds | length')"

# `--full` outranks the cut: the row it names comes back verbatim, the way it
# outranks the adapter's clip, and every other row stays cut.
check "--full keeps the named round whole" \
  "$(jq -rn --argjson r "$round" '$r.body')" \
  "$(ship_brief "$poll" Gharib89 on_head '["11"]' | jq -r '.rounds[0].body')"

# A body the adapter already clipped must not come back looking complete, or the
# loop never learns to re-poll it with --full.
clipped_source=$(jq -cn --argjson r "$round" '
  {head_sha: "abc1234", mergeable: "clean", landed_by: null,
   reviews: {on_head: [$r + {body: ($r.body + "\n...[truncated]")}], all: [], total: 1},
   threads: []}')
check "a clipped body keeps its truncation marker through the cut" \
  "$(printf '%s\n...[truncated]' "$findings")" \
  "$(ship_brief "$clipped_source" Gharib89 on_head | jq -r '.rounds[0].body')"

# Both sides of the comparison lose the `[bot]` suffix: a run authenticated as a
# bot carries it on its own identity, and comparing it against a stripped login
# would leave its own rows in the reviewer's list.
check "a bot identity still matches its own row" 1 \
  "$(ship_brief "$poll" 'Gharib89[bot]' on_head | jq '.rounds | length')"

# `poll-pr --brief` refuses an unreadable identity as tooling before it polls,
# so this is the function's floor rather than a shape a run sees: given no
# identity it drops nothing, never every row.
check "an unreadable identity drops no row" 2 \
  "$(ship_brief "$unawaited" "" on_head | jq '.rounds | length')"

# Under --reviewer the rounds are that reviewer's alone: on #255 a poll awaiting
# claude listed Copilot's quota notice as a round of claude's.
quota='{"id":20,"login":"copilot-pull-request-reviewer[bot]","state":"comment","substantive":false,
        "submitted_at":"2026-09-14T04:00:00Z","body":"Copilot was unable to review this pull request."}'
claude_round='{"id":21,"login":"claude[bot]","state":"comment","substantive":true,
               "submitted_at":"2026-09-14T04:10:00Z","body":"- a claude finding"}'
fallback=$(jq -cn --argjson q "$quota" --argjson c "$claude_round" --argjson m "$mine" '
  {head_sha: "abc1234", mergeable: "clean", landed_by: "since",
   reviews: {on_head: [$q, $c, $m], all: [$q, $c, $m], total: 3}, threads: [],
   reviewer: {name: "claude", login: "Claude[bot]", rule: "since", await_run: null, timeout: 480}}')
check "under --reviewer rounds[] holds only that reviewer's rows" '[21]' \
  "$(ship_brief "$fallback" Gharib89 all | jq -c '[.rounds[].id]')"

# A round with no finding items still has to be readable, so it is clipped the
# way the adapters clip a long body.
prose=$(rep 240 p)
clipped=$(jq -cn --argjson r "$round" --arg b "$prose" '
  {head_sha: "abc1234", mergeable: "clean", landed_by: null,
   reviews: {on_head: [$r + {body: $b}], all: [], total: 1}, threads: []}')
check "a round with no items is clipped, not emptied" \
  "$(printf '%s\n...[truncated]' "$(rep 200 p)")" \
  "$(ship_brief "$clipped" Gharib89 on_head | jq -r '.rounds[0].body')"

# CommonMark lets a bullet carry any whitespace between the marker and the text,
# and a reviewer that aligns its items behind `1.` writes two spaces. A matcher
# that demanded exactly one space read such a round as item-less and cut it to
# its first 200 characters, dropping the findings the poll came for.
wide=$(printf 'Approval recommended\n\n-  a wide bullet\n1.\ta tab bullet\n%s' "$(rep 240 p)")
spaced=$(jq -cn --argjson r "$round" --arg b "$wide" '
  {head_sha: "abc1234", mergeable: "clean", landed_by: null,
   reviews: {on_head: [$r + {body: $b}], all: [], total: 1}, threads: []}')
check "a bullet with wide whitespace after its marker is a finding item" \
  "$(printf 'Approval recommended\n-  a wide bullet\n1.\ta tab bullet')" \
  "$(ship_brief "$spaced" Gharib89 on_head | jq -r '.rounds[0].body')"

# A thread row is what a run dispositions: `path` says which file the finding is
# on and `lead` says what it is, so one Copilot thread can be answered off the
# brief instead of a second poll for the full shape. The lead is the first line
# with text in it: a thread body that opens on a blank line or a fenced
# suggestion below carries its verdict on that line and nothing else.
leads=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [], all: [], total: 0},
  threads: [{id: "t3", resolved: false, replied: false, author: "Copilot",
             path: "skills/ship/scripts/ci-wait.sh",
             body: "\n\nthe grace is read twice\n\n```suggestion\ngrace=0\n```"},
            {id: "t4", resolved: false, replied: false, author: "Copilot",
             path: null, body: "a round finding naming no file"}]}')

check "a multi-line thread body comes down to its first line with text" \
  'the grace is read twice' \
  "$(ship_brief "$leads" Gharib89 on_head | jq -r '.threads[0].lead')"

# A thread the host attached to no file (a review-body finding) keeps the null
# rather than an empty string: the two read differently to a run choosing
# between `reply-thread` and `comment-pr`.
check "a thread on no file carries a null path" \
  null "$(ship_brief "$leads" Gharib89 on_head | jq -c '.threads[1].path')"

# The lead is cut at the width the rounds' finding items use, and carries the
# same marker, so a thread whose first line is an essay does not cost the brief
# its brevity.
long=$(jq -cn --arg b "$(rep 240 t)" '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [], all: [], total: 0},
  threads: [{id: "t5", resolved: false, replied: false, author: "Copilot",
             path: "skills/ship/scripts/poll-pr.sh", body: $b}]}')
check "a long lead is cut at the finding-items width and says so" \
  "$(printf '%s\n...[truncated]' "$(rep 200 t)")" \
  "$(ship_brief "$long" Gharib89 on_head | jq -r '.threads[0].lead')"

# A thread with nothing in its body still produces a row: the id is what
# `resolve-thread` takes, and a row dropped for an empty lead is a disposition
# the run never makes.
empty=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [], all: [], total: 0},
  threads: [{id: "t6", resolved: false, replied: false, author: "Copilot", path: "x.sh", body: ""}]}')
check "an empty thread body leaves an empty lead, not a missing row" \
  '{"id":"t6","path":"x.sh","lead":"","resolved":false,"replied":false}' \
  "$(ship_brief "$empty" Gharib89 on_head | jq -c '.threads[0]')"

# `threads` is the string "unavailable" when the host refused the state; the
# projection reports that rather than an empty list, which would read as "no
# threads left to answer".
unreadable=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [], all: [], total: 0}, threads: "unavailable"}')
check "unreadable thread state passes through as the string" \
  '"unavailable"' "$(ship_brief "$unreadable" Gharib89 on_head | jq -c '.threads')"

finish
