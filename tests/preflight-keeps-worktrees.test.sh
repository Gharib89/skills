#!/usr/bin/env bash
# Starting a run never deletes a worktree (#1339). A worktree at a merged PR's
# head, with an untracked file, an ignored file and its branch, is left exactly
# as it is by a preflight that admits the issue and by one that refuses it, and
# the answer carries no `pruned` field.
#
# Driven at preflight's own entrypoint over the Host fake inside a throwaway
# checkout whose origin is a local bare repo (a `git` shim answers
# `remote get-url origin` with the GitHub URL host detection needs). The
# checkout carries this repo's profile, skills lock and workflow so an open,
# triaged issue is admitted.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

root=$PWD
scripts=$root/skills/ship-run/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
real_git=$(command -v git)
g() { "$real_git" -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$root/tests/host-fake.sh
export GIT_ALLOW_PROTOCOL=file
mkdir -p "$SHIP_FAKE" "$work/bin"
{
  g init -q --bare "$work/origin.git"
  g clone -q "$work/origin.git" "$work/repo"
  cd "$work/repo"
  mkdir -p docs/agents .github/workflows
  cp "$root/docs/agents/ship.md" docs/agents/
  cp "$root/skills-lock.json" .
  cp "$root/.github/workflows/claude-review.yml" .github/workflows/
  cp -r "$root/.claude" .
  printf '.claude/worktrees/\nscratch.log\n' > .gitignore
  g add -A && g commit -q -m init && g push -q origin main
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
cat > "$work/bin/git" <<SHIM
#!/usr/bin/env bash
[ "\$*" = "remote get-url origin" ] && { echo https://github.com/owner/repo.git; exit 0; }
exec "$real_git" "\$@"
SHIM
chmod +x "$work/bin/git"

repo=$work/repo
wt=$repo/.claude/worktrees/old-9
g -C "$repo" worktree add -q -b fix/old-9 "$wt" >/dev/null 2>&1
printf 'work\n' > "$wt/untracked.txt"
printf 'build\n' > "$wt/scratch.log"

printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"
# The PR record the removed prune keyed on: kept so this test goes red again if
# the prune returns.
jq -n --arg h "$(g -C "$wt" rev-parse HEAD)" '{number: 7, state: "merged", head_sha: $h}' \
  > "$SHIP_FAKE/host_pr_for_branch.1.json"
issue() { # <state>
  jq -n --arg s "$1" '{number: 5, state: $s, is_pr: false, title: "t", body: "", labels: ["ready-for-agent"], assignees: [], comments: [], blockers: []}' \
    > "$SHIP_FAKE/host_issue_get.1.json"
}
preflight() { ( cd "$repo" && PATH="$work/bin:$PATH" bash "$scripts/preflight.sh" 5 2>/dev/null ); }
left() { # the state a preflight leaves behind
  printf '%s %s %s %s' "$([ -d "$wt" ] && echo dir || echo gone)" \
    "$([ -f "$wt/untracked.txt" ] && echo untracked || echo lost)" \
    "$([ -f "$wt/scratch.log" ] && echo ignored || echo lost)" \
    "$(g -C "$repo" branch --list --format='%(refname:short)' fix/old-9)"
}
kept='dir untracked ignored fix/old-9'

issue closed; out=$(preflight); rc=$?
check "a refused preflight exits 1" 1 "$rc"
check "and refuses on the issue" '["closed"]' "$(jq -c .reasons <<<"$out")"
check "and leaves the merged PR's worktree, its files and branch" "$kept" "$(left)"
check "and carries no pruned field" false "$(jq 'has("pruned")' <<<"$out")"

issue open; out=$(preflight); rc=$?
check "an admitted preflight exits 0" 0 "$rc"
check "and admits" true "$(jq .ok <<<"$out")"
check "and leaves the same worktree, its files and branch" "$kept" "$(left)"
check "and carries no pruned field" false "$(jq 'has("pruned")' <<<"$out")"

finish
