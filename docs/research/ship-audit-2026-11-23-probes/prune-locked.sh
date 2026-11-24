#!/usr/bin/env bash
# preflight's prune on a locked worktree at its merged PR's head: the removal
# fails on the lock, yet pruned[] names the worktree. Driven over the Host fake
# inside a throwaway GitHub-origin checkout. Run from the repo root.
set -uo pipefail
scripts=$PWD/skills/ship-run/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh GIT_ALLOW_PROTOCOL=file
mkdir -p "$repo" "$SHIP_FAKE"
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
g init -q
g remote add origin https://github.com/owner/repo.git
g commit -q --allow-empty -m base
wt=$repo/.claude/worktrees/locked
g worktree add -q -b fix/locked "$wt" >/dev/null 2>&1
g worktree lock "$wt"
printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"
jq -n --arg h "$(git -C "$wt" rev-parse HEAD)" '{number: 7, state: "merged", head_sha: $h}' \
  > "$SHIP_FAKE/host_pr_for_branch.1.json"

echo "pruned[] from preflight: $(cd "$repo" && bash "$scripts/preflight.sh" none 2>/dev/null | jq -c --arg r "$repo/" '.pruned | map(ltrimstr($r))')"
echo "worktree directory still present: $([ -d "$wt" ] && echo yes || echo no)"
echo "local branch still present: $(g branch --list --format='%(refname:short)' fix/locked)"
