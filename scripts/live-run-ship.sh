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
# ship_body_closes: a PR closes the issue the way Ship reads it.
# shellcheck source=../skills/ship/scripts/_lib.sh
source "$here/../skills/ship/scripts/_lib.sh"
tmp=$(mktemp -d)
co=$tmp/fixture
issue=""
tooling() { echo "$1" >&2; exit 2; }

open_prs() { # -> [{number, body, head}], every page
  gh api --paginate "repos/$repo/pulls?state=open&per_page=100" \
    --jq '.[] | {number, body, head: .head.ref}' | jq -s .
}
# A PR is the run's when its head is a Ship branch, `<type>/<slug>-<issue>`, or
# its body closes the issue.
run_prs() { # <open_prs json> -> one PR number per line
  local i=0
  while [ "$i" -lt "$(jq length <<<"$1")" ]; do
    if jq -e --argjson i "$i" --arg s "-$issue" '.[$i].head | endswith($s)' <<<"$1" >/dev/null \
      || ship_body_closes "$(jq -r --argjson i "$i" '.[$i].body // ""' <<<"$1")" "$issue"; then
      jq --argjson i "$i" '.[$i].number' <<<"$1"
    fi
    i=$(( i + 1 ))
  done
}
run_branches() {
  gh api --paginate "repos/$repo/branches?per_page=100" --jq ".[].name | select(endswith(\"-$issue\"))"
}

# Close the run's issue and PRs and delete its branches.
reset_host() {
  [ -n "$issue" ] || return 0
  local prs n b
  if prs=$(open_prs); then
    for n in $(run_prs "$prs"); do gh api -X PATCH "repos/$repo/pulls/$n" -f state=closed >/dev/null; done
  fi
  for b in $(run_branches); do gh api -X DELETE "repos/$repo/git/refs/heads/$b" >/dev/null; done
  gh api -X PATCH "repos/$repo/issues/$issue" -f state=closed -f state_reason=not_planned >/dev/null
}
trap 'reset_host; rm -rf "$tmp"' EXIT
trap 'exit 2' INT TERM

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

issue=$(gh api "repos/$repo/issues" -f title='Add a sub helper to calc.sh' -f 'labels[]=ready-for-agent' \
  -f body="$(cat <<'BODY'
## What to build

`calc.sh` has `add`. Add `sub`, which prints its first argument minus its second, the same way `add` prints a sum.

## Acceptance criteria

- [ ] `sub 5 3` prints `2`, and `sub 3 5` prints `-2`.
- [ ] `test.sh` checks both cases.
BODY
)" --jq .number) || tooling "cannot file the issue on $repo"

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
pr=$(run_prs "$prs" | head -n 1)
PR_TEMPLATE=$co/.github/pull_request_template.md \
  "$here/live-run-checks.sh" "${run_file:-$tmp/no-run-file}" "$tmp/host.json" "$issue" > "$tmp/failed"
[ $? -le 1 ] || tooling "live-run-checks.sh failed as tooling"

# Reset, then read the fixture back: a read that fails leaves cleanup unproven.
reset_host
if state=$(gh api "repos/$repo/issues/$issue" --jq .state) && prs=$(open_prs) && branches=$(run_branches); then
  { [ "$state" = closed ] || echo "cleanup: left issue #$issue open"
    for n in $(run_prs "$prs"); do echo "cleanup: left PR #$n open"; done
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
