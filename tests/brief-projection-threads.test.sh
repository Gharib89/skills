#!/usr/bin/env bash
# Split by behaviour from tests/brief-projection.test.sh: thread row cases.
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

# A thread row is what a run dispositions: `path` says which file the finding is
# on and `lead` says what it is, so one Copilot thread can be answered off the
# brief instead of a second poll for the full shape. The lead is the first line
# with text in it, and a body with text past that line ends in the truncation
# marker: a finding in a later paragraph, or the fenced suggestion below a
# Copilot verdict, is text nobody has read, and an unmarked lead reads as the
# whole comment, so the loop never re-polls it with `--full` (#328).
leads=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [], all: [], total: 0},
  threads: [{id: "t3", resolved: false, replied: false, author: "Copilot",
             path: "skills/ship/scripts/ci-wait.sh",
             body: "\n\nthe grace is read twice\n\n```suggestion\ngrace=0\n```"},
            {id: "t4", resolved: false, replied: false, author: "Copilot",
             path: null, body: "a round finding naming no file"}]}')

check "a multi-line thread body comes down to its first line with text, marked" \
  "$(printf 'the grace is read twice\n...[truncated]')" \
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

# Blank lines are not text: a single line padded with them was read whole and
# takes no marker, a browser-typed `\r` blank line included. A long first line
# that also drops later lines was cut twice and says so once, the way a clipped
# round's finding items carry a single marker.
padded=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [], all: [], total: 0},
  threads: [{id: "t8", resolved: false, replied: false, author: "Copilot", path: "x.sh",
             body: "\n\n  one line, whole  \n\n"}]}')
check "a single line padded with blank lines is not marked" \
  '  one line, whole  ' "$(ship_brief "$padded" Gharib89 on_head | jq -r '.threads[0].lead')"
crlf=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [], all: [], total: 0},
  threads: [{id: "t10", resolved: false, replied: false, author: "claude", path: "x.sh",
             body: "typed in the browser\r\n\r\n"}]}')
check "a CRLF blank line is not text" \
  "$(printf 'typed in the browser\r')" "$(ship_brief "$crlf" Gharib89 on_head | jq -r '.threads[0].lead')"
both=$(jq -cn --arg b "$(rep 240 t)"$'\n\n'"a later paragraph" '{head_sha: "abc1234", mergeable: "clean",
  landed_by: null, reviews: {on_head: [], all: [], total: 0},
  threads: [{id: "t9", resolved: false, replied: false, author: "Copilot", path: "x.sh", body: $b}]}')
check "a long multi-line lead carries one marker" \
  "$(printf '%s\n...[truncated]' "$(rep 200 t)")" \
  "$(ship_brief "$both" Gharib89 on_head | jq -r '.threads[0].lead')"

# `--full` outranks the thread cut too: a clipped lead is one the loop re-polls
# with `--full <id>`, and a re-poll handing back the same cut sends the run to a
# read no mechanic performs (#327). The named row's lead is its whole body, every
# line of it, and the unnamed rows keep the cut.
whole="$(rep 240 w)"$'\n\n'"the second paragraph"
named=$(jq -cn --arg b "$whole" --arg t "$(rep 240 t)" '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [], all: [], total: 0},
  threads: [{id: "t7", resolved: false, replied: false, author: "claude", path: "x.sh", body: $b},
            {id: "t5", resolved: false, replied: false, author: "Copilot", path: "y.sh", body: $t}]}')
check "--full keeps the named thread's body whole" \
  "$whole" "$(ship_brief "$named" Gharib89 on_head '["t7"]' | jq -r '.threads[0].lead')"
check "--full leaves an unnamed thread cut" \
  "$(printf '%s\n...[truncated]' "$(rep 200 t)")" \
  "$(ship_brief "$named" Gharib89 on_head '["t7"]' | jq -r '.threads[1].lead')"

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

# `--full open` is every row whole: the ids a run does not have yet are the ones
# it wants verbatim.
bulk=$(jq -cn --arg b "$(rep 240 w)"$'\n\n'"the second paragraph" '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [{id: "r1", login: "claude[bot]", substantive: true, submitted_at: "2026-09-14T04:10:00Z", body: $b}],
            all: [], total: 1},
  threads: [{id: "t1", resolved: false, replied: false, author: "claude", path: "x.sh", body: $b},
            {id: "t2", resolved: true, replied: false, author: "claude", path: "x.sh", body: $b}]}')
whole_bulk="$(rep 240 w)"$'\n\n'"the second paragraph"
check "--full open returns every open thread's lead whole" \
  "$whole_bulk" "$(ship_brief "$bulk" Gharib89 on_head '["open"]' | jq -r '.threads[0].lead')"
check "--full open returns every round whole" \
  "$whole_bulk" "$(ship_brief "$bulk" Gharib89 on_head '["open"]' | jq -r '.rounds[0].body')"
check "--full open leaves the resolved thread out as it always does" 1 \
  "$(ship_brief "$bulk" Gharib89 on_head '["open"]' | jq '.threads | length')"
check "without --full the same rows are cut" \
  "$(printf '%s\n...[truncated]' "$(rep 200 w)")" \
  "$(ship_brief "$bulk" Gharib89 on_head | jq -r '.threads[0].lead')"

# A Copilot overview review, as the host serves it (tests/fixtures/, PR 475's
# review 5406886174): HTML comment, tags, nested `<details>` and a `Findings:`
# count. It says `Findings: None` and still carries a finding, under `Previously
# missed`, which has no thread and no bullet of its own. The loop acts on its
# verdict line, its findings line and the open and missed items, not on the
# markup, the `What changed` table or what a later round already resolved.
overview() { # <fixture>: one round with that file as its body, projected
  local f=$1
  jq -cn --rawfile b "tests/fixtures/$f" '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
    reviews: {on_head: [{id: 1, login: "copilot-pull-request-reviewer[bot]", substantive: true,
                         submitted_at: "2026-09-14T03:00:00Z", body: $b}], all: [], total: 1},
    threads: []}' | { read -r src; ship_brief "$src" Gharib89 on_head | jq -r '.rounds[0].body'; }
}
missed=$(overview copilot-overview.md)
check "a Findings: None overview keeps its verdict heading and line, its findings line and the missed item" \
  "🔵 Needs a closer look: Empty or whitespace-only locks still allow installation without skill selectors, installing every upstream skill.|**Findings:** None|- Empty skills lock bypasses guard and installs all skills" \
  "$(sed -n '1p;2p' <<<"$missed" | paste -sd'|' -)|$(sed -n 3p <<<"$missed" | sed 's/: .*//')"
check "the missed item rides one line, its location after the title" 3 "$(wc -l <<<"$missed" | tr -d ' ')"
check "the markup is gone: no tag, no comment" 0 "$(grep -cE '<[A-Za-z/!]' <<<"$missed")"
check "what a later round resolved is not a finding" 0 "$(grep -c 'Shell command injection' <<<"$missed")"
open=$(overview copilot-overview-open.md)
check "an overview with open findings keeps its lead, its count and one item each" \
  "🟡 Changes recommended: Compare pagination is unspecified, so ranges exceeding 30 commits can still omit subjects.|$(printf '%s' '**Findings:** 2')|2" \
  "$(sed -n 1p <<<"$open")|$(sed -n 2p <<<"$open" | sed 's/ *$//')|$(grep -c '^- ' <<<"$open")"
check "an overview's open items keep their text and drop the severity badge" 2 \
  "$(grep -c '^- \[Follow pagination when fetching compare commits\](#discussion_r' <<<"$open")"
check "an overview's What changed block is not a finding" 0 "$(grep -c 'Intersects path-filtered\|Standards' <<<"$open")"
check "no tag or comment is left in an open-findings overview either" 0 "$(grep -cE '<[A-Za-z/!]' <<<"$open")"

# The same round, written by hand: `Findings: None` plus a `<details>` item.
synthetic=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [{id: 1, login: "copilot-pull-request-reviewer[bot]", substantive: true,
    submitted_at: "2026-09-14T03:00:00Z",
    body: "<!-- v2\nhidden -->\n## Overview\n\nLooks fine.\n\n**Findings:** None\n\n<details><summary>Previously missed</summary>\n\n- item\n</details>"}],
    all: [], total: 1}, threads: []}')
check "a Findings: None round returns the item in its details block" \
  "$(printf 'Looks fine.\n**Findings:** None\n- item')" \
  "$(ship_brief "$synthetic" Gharib89 on_head | jq -r '.rounds[0].body')"

# An overview states its verdict as an h3 heading before the summary sentence, and
# it is the round's only severity word, so the lead keeps it ahead of the
# sentence. The h1 and h2 headings above it are titles and stay skipped, and a
# heading after the lead is not a verdict.
verdict=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [{id: 1, login: "copilot-pull-request-reviewer[bot]", substantive: true,
    submitted_at: "2026-09-14T03:00:00Z",
    body: "# Title\n\n## Overview\n\n### Needs a closer look\n\nSummary sentence.\n\n### Later heading\n\n- item"}],
    all: [], total: 1}, threads: []}')
check "an h3 verdict heading leads the summary sentence, hashes stripped, h1 and h2 skipped" \
  "$(printf 'Needs a closer look: Summary sentence.\n- item')" \
  "$(ship_brief "$verdict" Gharib89 on_head | jq -r '.rounds[0].body')"
check "a body with no h3 verdict keeps the bare lead" \
  "$(printf 'Looks fine.\n**Findings:** None\n- item')" \
  "$(ship_brief "$synthetic" Gharib89 on_head | jq -r '.rounds[0].body')"

# The adapter clips at 2000 characters wherever that falls, a tag or a comment
# included: the cut must not leave `<` behind, and the marker still says so.
cut=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [{id: 1, login: "copilot-pull-request-reviewer[bot]", substantive: true,
    submitted_at: "2026-09-14T03:00:00Z",
    body: "## Overview\n\nLead here\n\n**Findings:** 1 <picture><source media=\"(pref\n...[truncated]"}],
    all: [], total: 1}, threads: []}')
check "a body cut inside a tag loses the tag and keeps the marker" \
  "$(printf 'Lead here\n**Findings:** 1\n...[truncated]')" \
  "$(ship_brief "$cut" Gharib89 on_head | jq -r '.rounds[0].body')"

# A finding that quotes a usage line keeps its placeholders: only real HTML tag
# names are markup, so `<n>`, `<name>` and `<word>` survive inside a code span
# and outside one.
usage=$(jq -cn '{head_sha: "abc1234", mergeable: "clean", landed_by: null,
  reviews: {on_head: [{id: 1, login: "copilot-pull-request-reviewer[bot]", substantive: true,
    submitted_at: "2026-09-14T03:00:00Z",
    body: "## Overview\n\nLooks fine.\n\n**Findings:** 2\n\n- usage reads run-file close <n> --result <name>=<word> here\n- `run-file close <n> --result <name>=<word>` in a span <b>bold</b>"}],
    all: [], total: 1}, threads: []}')
check "a usage line quoted in a finding keeps its placeholders, real tags still go"   "$(printf 'Looks fine.\n**Findings:** 2\n- usage reads run-file close <n> --result <name>=<word> here\n- `run-file close <n> --result <name>=<word>` in a span bold')"   "$(ship_brief "$usage" Gharib89 on_head | jq -r '.rounds[0].body')"

# review-loop.md is what a run reads a brief by, and a thread row's text is
# `lead` where a round row's is `body`: a run that read `.body` off a thread got
# null and took the comment over REST instead (#590). The loop's `--brief`
# bullet names each field the projection emits on a thread row and says the row
# has no `body`; a negated copy of the bullet must fail each half.
loop_brief=$(awk '/^- \*\*`--brief` is how a round is read/ {on=1; print; next}
  on && /^- \*\*/ {exit} on' skills/ship/reference/review-loop.md)
thread_keys=$(ship_brief "$poll" Gharib89 on_head | jq -r '.threads[0] | keys_unsorted[]')
# <bullet>: each thread-row field the bullet leaves unnamed, then `body` where it
# does not say a thread row has none.
unnamed() {
  local k
  for k in $thread_keys; do grep -qF "\`$k\`" <<<"$1" || echo "$k"; done
  grep -qF 'A thread row has no `body`' <<<"$1" || echo body
}
check "review-loop.md's --brief bullet names every thread-row field and denies a body" "" \
  "$(unnamed "$loop_brief")"
check "a bullet saying a thread row has a body is refused" body \
  "$(unnamed "${loop_brief//has no \`body\`/has a \`body\`}")"
check "a bullet that does not name \`lead\` is refused" lead \
  "$(unnamed "${loop_brief//\`lead\`/lead}")"

finish
