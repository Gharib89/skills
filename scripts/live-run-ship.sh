#!/usr/bin/env bash
# Ship's live run, the `ship-live-run` Verification in docs/agents/ship.md, also
# started by hand: real `/ship --unattended` turns, driven headless on the
# fixture repo, each judged from what it left behind
# (scripts/live-run-checks.sh). ADR 0008 says why a standing GitHub repo and not
# the host fake.
#
#   scripts/live-run-ship.sh <ship-source>
#   <ship-source>: a checkout of this repo, usually a worktree, whose skills/ship
#                  is the Ship under test; installed into the fixture with
#                  `npx skills add <ship-source> --skill ship`
#   LIVE_RUN_REPO: the fixture repo, default Gharib89/ship-fixture. Its `main`
#                  must sit at its `seed` tag, which carries the ship profile
#                  and every skill Ship composes at its pin.
#   LIVE_RUN_WALL_S: the wall-clock cap per run in seconds, default 1800
#
# Two paths, each on its own fresh issue and a fresh copy of the fixture: the
# happy path, a plain issue Ship must take to the merge gate, and the ambiguous
# path, a deliberately vague issue Ship must stop `ambiguous` on with no claim,
# no branch and no PR. Each runs `claude -p --model sonnet --permission-mode
# auto` with `/ship <n> --unattended`, then closes the issue and every PR from
# the run and deletes its branches, pass or fail. That cleanup is this script's
# scaffolding, not a Ship mechanic.
#
# Pass rule: a path that fails re-runs once on a new issue, and a pass on the
# retry is a pass, its first attempt's failures kept in `retried`. A cleanup the
# first attempt left undone still fails the result. Each run is capped by
# `--max-budget-usd` and the wall clock; hitting either is a failed check. What
# keeps a run from happening or from being read (a missing tool, a failed
# install, claude failing to run, the fixture repo unreachable) is `unavailable`.
#
# stdout: one JSON line {result: pass|fail, failed[], retried[], runs[]}, each
#         failure `<path>: <check>: <what failed>`, each run {path, attempt,
#         issue, pr, failed[], cost_usd, wall_s, session};
#         or {result: unavailable, reason}
# exit:   0 pass · 1 a check failed · 2 unavailable, or a usage error or no jq,
#         which print on stderr only
set -uo pipefail

[ $# -eq 1 ] || { echo 'usage: scripts/live-run-ship.sh <ship-source>' >&2; exit 2; }
command -v jq >/dev/null || { echo 'jq not installed' >&2; exit 2; }
unavailable() { jq -cn --arg r "$1" '{result: "unavailable", reason: $r}'; exit 2; }
src=$(cd "$1" 2>/dev/null && pwd) || src=""
[ -f "$src/skills/ship/SKILL.md" ] || unavailable "not a ship source: $1 (no skills/ship/SKILL.md)"
for t in gh git npx claude timeout; do
  command -v "$t" >/dev/null || unavailable "$t not installed"
done
repo=${LIVE_RUN_REPO:-Gharib89/ship-fixture}
# Caps per claude run, set from the baseline of 4 happy-path runs: cost median
# $1.01, highest $1.25, so twice the highest; wall clock median 166 s, highest
# 189 s, under the 30 minutes the Verification allows.
budget=2.50
wall_cap=${LIVE_RUN_WALL_S:-1800}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# ship_body_closes: a PR closes the issue the way Ship reads it. This checkout's
# copy rather than <ship-source>'s, so a Ship under test cannot change how it is
# judged; the profile's Run line runs this script from the default branch.
# shellcheck source=../skills/ship/scripts/_lib.sh
source "$here/../skills/ship/scripts/_lib.sh"
tmp=$(mktemp -d)
# Armed before anything else can be interrupted; reset_host is a no-op until
# the issue exists.
trap 'reset_host; rm -rf "$tmp"' EXIT
trap 'exit 2' INT TERM
base=$tmp/fixture
issue=""
mark="" # set just before the issue create; see marked_issue
run_heads="" # head branches of the run's PRs, gathered as reset_host closes them

open_prs() { # -> [{number, body, head}], every page
  gh api --paginate "repos/$repo/pulls?state=open&per_page=100" \
    --jq '.[] | {number, body, head: .head.ref}' | jq -s .
}
# A PR is the run's when its head is a Ship branch, `<type>/<slug>-<issue>`, or
# its body closes the issue. Returns 2 when a read fails, so no caller takes a
# failed read for "not the run's".
run_prs() { # <open_prs json> -> `<number> <head>` per line
  local i=0 rc
  while [ "$i" -lt "$(jq length <<<"$1")" ]; do
    jq -e --argjson i "$i" --arg s "-$issue" '.[$i].head | endswith($s)' <<<"$1" >/dev/null
    rc=$?
    if [ "$rc" -eq 1 ]; then
      ship_body_closes "$(jq -r --argjson i "$i" '.[$i].body // ""' <<<"$1")" "$issue"
      rc=$?
    fi
    case $rc in
      0) jq -r --argjson i "$i" '"\(.[$i].number) \(.[$i].head)"' <<<"$1" ;;
      1) ;;
      *) echo 'run_prs: a PR read failed' >&2; return 2 ;;
    esac
    i=$(( i + 1 ))
  done
}
# The run's branches: a Ship branch by its suffix, or the head of a PR the run
# opened, which a body match finds whatever its name.
run_branches() { # -> one branch name per line
  local names b
  names=$(gh api --paginate "repos/$repo/branches?per_page=100" --jq '.[].name') || return 2
  for b in $names; do
    case $b in
      *"-$issue") echo "$b" ;;
      *) case " $run_heads " in *" $b "*) echo "$b" ;; esac ;;
    esac
  done
}

# The open issue carrying this invocation's marker, or nothing.
# Returns 2 when the read fails, which is not "no such issue".
marked_issue() {
  local list
  list=$(gh api "repos/$repo/issues?state=open&sort=created&direction=desc&per_page=10") || return 2
  jq -e 'type == "array"' <<<"$list" >/dev/null 2>&1 || return 2
  jq -r --arg m "$mark" '[.[] | select(.pull_request == null and ((.body // "") | contains($m)))][0].number // empty' \
    <<<"$list" || return 2
}

# Close the run's issue and PRs and delete its branches. A read, close or delete
# that fails is said on stderr and returns 2: on the EXIT-trap path no read-back
# follows, so this is the only report a tooling exit or a Ctrl-C leaves.
reset_host() {
  # A signal can land while the create's response is in flight: the issue may
  # exist with its number unknown, so look for it by the marker.
  if [ -z "$issue" ] && [ -n "$mark" ]; then
    issue=$(marked_issue) || { echo "cleanup: unverified, the issue could not be re-read" >&2; return 2; }
  fi
  [ -n "$issue" ] || return 0
  local prs mine n h b branches rc=0
  if prs=$(open_prs) && mine=$(run_prs "$prs"); then
    while read -r n h; do
      [ -n "$n" ] || continue
      gh api -X PATCH "repos/$repo/pulls/$n" -f state=closed >/dev/null \
        || { echo "cleanup: PR #$n not closed" >&2; rc=2; }
      run_heads="$run_heads $h"
    done <<<"$mine"
  else
    echo "cleanup: unverified, the open PRs could not be read" >&2; rc=2
  fi
  if branches=$(run_branches); then
    # The branch is URI-encoded: a `#` in it would otherwise address another ref.
    for b in $branches; do
      gh api -X DELETE "repos/$repo/git/refs/heads/$(jq -rn --arg b "$b" '$b | @uri')" >/dev/null \
        || { echo "cleanup: branch $b not deleted" >&2; rc=2; }
    done
  else
    echo "cleanup: unverified, the branches could not be read" >&2; rc=2
  fi
  gh api -X PATCH "repos/$repo/issues/$issue" -f state=closed -f state_reason=not_planned >/dev/null \
    || { echo "cleanup: issue #$issue not closed" >&2; rc=2; }
  return "$rc"
}


gh repo clone "$repo" "$base" -- -q || unavailable "cannot clone $repo"
[ "$(git -C "$base" rev-parse origin/main)" = "$(git -C "$base" rev-parse -q --verify 'seed^{commit}')" ] \
  || unavailable "$repo: main is not at its seed tag; reset it before a live run"

# The install edits the tracked skills-lock.json and adds .claude/skills/ship/.
# Ship's in-place isolation refuses a dirty tree, so restore the one and exclude
# the other locally; Ship checks only the skills it composes against the lock.
(cd "$base" && npx -y skills add "$src" --skill ship --agent claude-code -y) >"$tmp/install.log" 2>&1 \
  || { tail -n 40 "$tmp/install.log" >&2; unavailable "ship install from $src failed"; }
git -C "$base" checkout -q -- .
git -C "$base" status --porcelain | sed -n 's/^?? //p' >> "$base/.git/info/exclude"

file_issue() { # <path> <attempt> <title> <body>: sets issue
  # A marker unique to this attempt, so a re-read finds this run's issue and
  # never another run's with the same title.
  mark="<!-- live-run: ${tmp##*/}-$1-$2 -->"
  issue=$(gh api "repos/$repo/issues" -f title="$3" -f 'labels[]=ready-for-agent' -f body="$mark
$4" --jq .number) || issue=""
  # A create whose response was lost may still have landed: re-read the newest
  # open issues for its marker before calling the create failed, so cleanup can
  # close it.
  if [ -z "$issue" ]; then
    issue=$(marked_issue) || unavailable "the issue create on $repo failed and its re-read failed too"
  fi
  [ -n "$issue" ] || unavailable "cannot file the issue on $repo"
}

happy_title='Add a sub helper to calc.sh'
happy_body=$(cat <<'BODY'
## What to build

`calc.sh` has `add`. Add `sub`, which prints its first argument minus its second, the same way `add` prints a sum.

## Acceptance criteria

- [ ] `sub 5 3` prints `2`, and `sub 3 5` prints `-2`.
- [ ] `test.sh` checks both cases.
BODY
)
# Deliberately vague: nothing in it says what to change, so Ship must stop
# `ambiguous` before it claims.
ambiguous_title='Fix calc.sh the way we discussed'
ambiguous_body='Do what we agreed on the call.'

# One Ship run of <path> on a new issue and a fresh copy of the fixture, judged,
# then reset. Appends its record to $tmp/runs; returns 0 pass, 1 fail.
attempt() { # <happy|ambiguous> <attempt>
  local co=$tmp/$1-$2 failed=$tmp/failed-$1-$2 rc start wall pr="" flag="" reply run_file assignees prs mine branches state n b
  cp -a "$base" "$co" || unavailable "cannot copy the fixture clone"
  if [ "$1" = happy ]; then file_issue "$1" "$2" "$happy_title" "$happy_body"
  else file_issue "$1" "$2" "$ambiguous_title" "$ambiguous_body"; flag=--ambiguous; fi

  start=$(date +%s)
  # -k: a claude that outlives SIGTERM by a minute is killed, and timeout then
  # exits 137 instead of 124; a 137 before the cap is claude killed by another hand.
  (cd "$co" && XDG_STATE_HOME=$tmp/state timeout -k 60 "$wall_cap" claude -p --model sonnet --permission-mode auto \
    --max-budget-usd "$budget" --output-format json "/ship $issue --unattended") >"$co.json" 2>"$co.err"
  rc=$?
  wall=$(( $(date +%s) - start ))
  : > "$failed"
  if [ "$rc" -eq 124 ] || { [ "$rc" -eq 137 ] && [ "$wall" -ge "$wall_cap" ]; }; then
    echo "cap: wall clock $wall_cap s" >> "$failed"
  elif [ "$rc" -ne 0 ] && [ "$(jq -r '.subtype? // empty' "$co.json" 2>/dev/null)" = error_max_budget_usd ]; then
    echo "cap: budget \$$budget" >> "$failed"
  elif [ "$rc" -ne 0 ]; then
    # Any other nonzero exit is claude failing (auth, quota, API), not Ship stopping.
    tail -n 40 "$co.err" >&2; unavailable "claude -p failed"
  else
    # An exit 0 with no reply string (no output, cut short, not JSON) is a failed
    # read; an empty string is what Ship said, and the checks judge it.
    reply=$(jq -er '.result | strings' "$co.json" 2>/dev/null) \
      || { head -c 2000 "$co.json" >&2; tail -n 40 "$co.err" >&2; unavailable "claude -p output unreadable"; }
    # The Run file sits under XDG_STATE_HOME, which this script pointed into $tmp.
    run_file=$(find "$tmp/state" -path "*/ship-$issue/run.md" 2>/dev/null | head -n 1)
    assignees=$(gh api "repos/$repo/issues/$issue" --jq '[.assignees[].login]') || unavailable "cannot read issue #$issue"
    prs=$(open_prs) || unavailable "cannot list PRs"
    mine=$(run_prs "$prs") || unavailable "cannot read the open PRs"
    branches=$(run_branches) || unavailable "cannot read the branches"
    jq -n --argjson a "$assignees" --argjson p "$prs" --arg b "$branches" \
      --arg r "$reply" \
      '{assignees: $a, open_prs: [$p[] | {number, body}], branches: ($b | split("\n") | map(select(. != ""))),
        reply: $r}' > "$co.host.json"
    pr=$(head -n 1 <<<"$mine" | cut -d ' ' -f 1)
    PR_TEMPLATE=$co/.github/pull_request_template.md \
      "$here/live-run-checks.sh" ${flag:+"$flag"} "${run_file:-$tmp/no-run-file}" "$co.host.json" "$issue" >> "$failed"
    [ $? -le 1 ] || unavailable "live-run-checks.sh failed as tooling"
  fi

  # Reset, then read the fixture back: a read that fails leaves cleanup unproven.
  reset_host
  if state=$(gh api "repos/$repo/issues/$issue" --jq .state) && prs=$(open_prs) && mine=$(run_prs "$prs") \
    && branches=$(run_branches); then
    { [ "$state" = closed ] || echo "cleanup: left issue #$issue open"
      while read -r n _; do [ -z "$n" ] || echo "cleanup: left PR #$n open"; done <<<"$mine"
      for b in $branches; do echo "cleanup: left branch $b"; done
    } >> "$failed"
  else
    echo "cleanup: unverified, a fixture read failed" >> "$failed"
  fi

  jq -cn --arg path "$1" --argjson attempt "$2" --rawfile f "$failed" --argjson issue "$issue" \
    --argjson pr "${pr:-null}" --argjson wall "$wall" --slurpfile c <(jq -c . "$co.json" 2>/dev/null || echo '{}') \
    '{path: $path, attempt: $attempt, issue: $issue, pr: $pr, failed: ($f | split("\n") | map(select(. != ""))),
      cost_usd: ($c[0].total_cost_usd // null), wall_s: $wall, session: ($c[0].session_id // null)}' >> "$tmp/runs"
  issue="" mark="" run_heads=""
  [ ! -s "$failed" ]
}

for path in happy ambiguous; do
  attempt "$path" 1 || attempt "$path" 2
done

# A first attempt that failed is the one retried; every other run is its path's
# final word. A retried run's cleanup failure stays a failure: its leftovers are
# still on the fixture whatever the retry did.
out=$(jq -cs 'def lines(f): .path as $p | .failed[] | select(f) | "\($p): \(.)";
  ([.[] | select(.attempt == 1 and .failed != [])]) as $retried
  | ([.[] | select(.attempt == 2 or .failed == [])]) as $final
  | ([$final[] | lines(true)] + [$retried[] | lines(startswith("cleanup: "))]) as $failed
  | {result: (if $failed == [] then "pass" else "fail" end),
     failed: $failed, retried: [$retried[] | lines(true)], runs: .}' "$tmp/runs")
printf '%s\n' "$out"
[ "$(jq -r .result <<<"$out")" = pass ]
