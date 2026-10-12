#!/usr/bin/env bash
# Ship's live run, started by hand: one real `/ship --unattended` turn, driven
# headless on the fixture repo, judged from what it left behind
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
#
# The run files a fresh issue, runs `claude -p --model sonnet --permission-mode
# auto` with `/ship <n> --unattended` in a fresh clone, then closes the issue and
# every PR from the run and deletes its branches, pass or fail. That cleanup is
# this script's scaffolding, not a Ship mechanic.
#
# stdout: one JSON line {pass, failed[], issue, pr, cost_usd, wall_s, session}
# exit:   0 pass · 1 a check failed · 2 tooling, before or around the run
set -uo pipefail

[ $# -eq 1 ] || { echo 'usage: scripts/live-run-ship.sh <ship-source>' >&2; exit 2; }
src=$(cd "$1" 2>/dev/null && pwd) || src=""
[ -f "$src/skills/ship/SKILL.md" ] || { echo "not a ship source: $1 (no skills/ship/SKILL.md)" >&2; exit 2; }
for t in gh jq git npx claude; do
  command -v "$t" >/dev/null || { echo "$t not installed" >&2; exit 2; }
done
repo=${LIVE_RUN_REPO:-Gharib89/ship-fixture}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# ship_body_closes: a PR closes the issue the way Ship reads it. This checkout's
# copy, never <ship-source>'s, so a Ship under test cannot change how it is judged.
# shellcheck source=../skills/ship/scripts/_lib.sh
source "$here/../skills/ship/scripts/_lib.sh"
tmp=$(mktemp -d)
# Armed before anything else can be interrupted; reset_host is a no-op until
# the issue exists.
trap 'reset_host; rm -rf "$tmp"' EXIT
trap 'exit 2' INT TERM
co=$tmp/fixture
issue=""
mark="" # set just before the issue create; see marked_issue
run_heads="" # head branches of the run's PRs, gathered as reset_host closes them
tooling() { echo "$1" >&2; exit 2; }

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

gh repo clone "$repo" "$co" -- -q || tooling "cannot clone $repo"
[ "$(git -C "$co" rev-parse origin/main)" = "$(git -C "$co" rev-parse -q --verify 'seed^{commit}')" ] \
  || tooling "$repo: main is not at its seed tag; reset it before a live run"

# The install edits the tracked skills-lock.json and adds .claude/skills/ship/.
# Ship's in-place isolation refuses a dirty tree, so restore the one and exclude
# the other locally; Ship checks only the skills it composes against the lock.
(cd "$co" && npx -y skills add "$src" --skill ship --agent claude-code -y) >"$tmp/install.log" 2>&1 \
  || { tail -n 40 "$tmp/install.log" >&2; tooling "ship install from $src failed"; }
git -C "$co" checkout -q -- .
git -C "$co" status --porcelain | sed -n 's/^?? //p' >> "$co/.git/info/exclude"

# A marker unique to this invocation, so a re-read finds this run's issue and
# never another run's with the same title.
mark="<!-- live-run: ${tmp##*/} -->"
issue=$(gh api "repos/$repo/issues" -f title='Add a sub helper to calc.sh' -f 'labels[]=ready-for-agent' \
  -f body="$mark
$(cat <<'BODY'
## What to build

`calc.sh` has `add`. Add `sub`, which prints its first argument minus its second, the same way `add` prints a sum.

## Acceptance criteria

- [ ] `sub 5 3` prints `2`, and `sub 3 5` prints `-2`.
- [ ] `test.sh` checks both cases.
BODY
)" --jq .number) || issue=""
# A create whose response was lost may still have landed: re-read the newest
# open issues for its marker before calling the create failed, so cleanup can
# close it.
if [ -z "$issue" ]; then
  issue=$(marked_issue) || tooling "the issue create on $repo failed and its re-read failed too"
fi
[ -n "$issue" ] || tooling "cannot file the issue on $repo"

start=$(date +%s)
# A nonzero exit is claude failing (auth, quota, API), not Ship stopping.
(cd "$co" && XDG_STATE_HOME=$tmp/state claude -p --model sonnet --permission-mode auto \
  --output-format json "/ship $issue --unattended") >"$tmp/claude.json" 2>"$tmp/claude.err" \
  || { tail -n 40 "$tmp/claude.err" >&2; tooling "claude -p failed"; }
wall=$(( $(date +%s) - start ))

# The Run file sits under XDG_STATE_HOME, which this script pointed into $tmp.
run_file=$(find "$tmp/state" -path "*/ship-$issue/run.md" 2>/dev/null | head -n 1)
assignees=$(gh api "repos/$repo/issues/$issue" --jq '[.assignees[].login]') || tooling "cannot read issue #$issue"
prs=$(open_prs) || tooling "cannot list PRs"
jq -n --argjson a "$assignees" --argjson p "$prs" '{assignees: $a, open_prs: [$p[] | {number, body}]}' > "$tmp/host.json"
pr=$(run_prs "$prs") || tooling "cannot read the open PRs"
pr=$(head -n 1 <<<"$pr" | cut -d ' ' -f 1)
PR_TEMPLATE=$co/.github/pull_request_template.md \
  "$here/live-run-checks.sh" "${run_file:-$tmp/no-run-file}" "$tmp/host.json" "$issue" > "$tmp/failed"
[ $? -le 1 ] || tooling "live-run-checks.sh failed as tooling"

# Reset, then read the fixture back: a read that fails leaves cleanup unproven.
reset_host
if state=$(gh api "repos/$repo/issues/$issue" --jq .state) && prs=$(open_prs) && mine=$(run_prs "$prs") \
  && branches=$(run_branches); then
  { [ "$state" = closed ] || echo "cleanup: left issue #$issue open"
    while read -r n _; do [ -z "$n" ] || echo "cleanup: left PR #$n open"; done <<<"$mine"
    for b in $branches; do echo "cleanup: left branch $b"; done
  } >> "$tmp/failed"
else
  echo "cleanup: unverified, a fixture read failed" >> "$tmp/failed"
fi

jq -cn --rawfile f "$tmp/failed" --argjson issue "$issue" --argjson pr "${pr:-null}" --argjson wall "$wall" \
  --slurpfile c <(jq -c . "$tmp/claude.json" 2>/dev/null || echo '{}') \
  '{pass: ($f == ""), failed: ($f | split("\n") | map(select(. != ""))), issue: $issue, pr: $pr,
    cost_usd: ($c[0].total_cost_usd // null), wall_s: $wall, session: ($c[0].session_id // null)}'
[ ! -s "$tmp/failed" ]
