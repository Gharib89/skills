#!/usr/bin/env bash
# super-agent's `reconcile` carries the status block on every answer, over fake
# `t3` and `gh` on PATH (tests/super-agent-fake.sh): only the rows that changed
# since the last block, Merged only for merges since then, and each new need
# raised once, by the block that alerts it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=Gharib89/skills
R() { bash "$s/reconcile.sh" --ledger "$led" "$@"; }
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }

# fixture: tickets 5 and 6, each with a running thread, no PR and an open issue
for n in 5 6; do
  L add --repo $repo --number $n --thread "t-$n" --worktree "/wt/$n" --branch "feat/x-$n" >/dev/null
  sa_thread "t-$n" running 1 0 "/wt/$n" "feat/x-$n"
  sa_pr $repo "feat/x-$n" none
  sa_issue $repo "$n" open
done

u=https://github.com/$repo
out=$(R --instance claude_small)
check "the first reconcile carries every row, then the instance line" \
  "Running (2): [skills#5]($u/issues/5) running, [skills#6]($u/issues/6) running
Super agent on claude_small" "$(jq -r .status.block <<<"$out")"
check "a reconcile with no row changed carries no block" 'false ' "$(R | jq -r '"\(.status.changed) \(.status.block)"')"
sa_issue $repo 30 open; L wait $repo#30 --reason r >/dev/null
check "a changed row is the only row it carries" "Waiting (1): [skills#30]($u/issues/30)" "$(R | jq -r .status.block)"
sa_pr $repo feat/x-5 merged; sa_thread t-5 idle 2 0 /wt/5 feat/x-5
check "a merge carries the Merged row and the Running row it changed" \
  "Merged (1): [skills#5]($u/issues/5) PR [7]($u/pull/7)
Running (1): [skills#6]($u/issues/6) running" "$(R | jq -r .status.block)"
check "the next reconcile does not list that merge again" "" "$(R | jq -r .status.block)"
sa_pr $repo feat/x-6 merged; sa_thread t-6 idle 2 0 /wt/6 feat/x-6
check "Merged lists only the merges since the last block, and an emptied row says none" \
  "Merged (1): [skills#6]($u/issues/6) PR [7]($u/pull/7)
Running: none" "$(R | jq -r .status.block)"
L need $repo#30 --action "Approve skills#30 scope fork" --reason scope --why "the issue allows both" --option "Approve it" --option "Hold it" >/dev/null
out=$(R)
check "a new need is raised" '["Gharib89/skills#30"]' "$(jq -c '[.status.raised[].key]' <<<"$out")"
check "and the needs-you message is carried" "**Approve [skills#30]($u/issues/30) scope fork?**" "$(jq -r .status.block <<<"$out" | head -n 1)"
check "the next reconcile raises it no more" '[]' "$(R | jq -c .status.raised)"
jq -cn '{providers: {claude_big: {driver: "claude", buckets: [{id: "week", window: "weekly", remaining: 0.4}]}}}' > "$tmp/q.json"
L wait $repo#31 --reason r >/dev/null; sa_issue $repo 31 open
check "--quota reaches status: a posted block ends with its Quota line" "Quota claude_big: weekly 40%, 5 hour unknown" "$(R --quota "$tmp/q.json" | jq -r .status.block | tail -1)"
L wait $repo#32 --reason r >/dev/null; sa_issue $repo 32 closed
before=$(cat "$led")
echo '[]' > "$tmp/nq.json"
check_rc "a --quota file that is not a quota read exits 2" 2 "$(R --quota "$tmp/nq.json" >/dev/null 2>&1; echo $?)"
check "before any write: the closed waiting row is still there for the next reconcile" "$before" "$(cat "$led")"
jq '.status = "x"' "$led" > "$tmp/l.json" && mv "$tmp/l.json" "$led"
out=$(R); rc=$?
check_rc "a status that fails after the write still exits 0" 0 "$rc"
check "and the answer keeps the row it shows only once, the status error with it" \
  "$repo#32 true" "$(jq -r '"\(.dropped[0].key) \(.status.error != null)"' <<<"$out")"
cp -r "$s" "$tmp/sc"; printf 'exit 1\n' > "$tmp/sc/status.sh" # a status that dies with no output
L wait $repo#33 --reason r >/dev/null; sa_issue $repo 33 closed
out=$(bash "$tmp/sc/reconcile.sh" --ledger "$led"); rc=$?
check_rc "a status dying silently still exits 0" 0 "$rc"
check "and the answer keeps its dropped row, the status error with it" \
  "$repo#33 status.sh failed" "$(jq -r '"\(.dropped[0].key) \(.status.error)"' <<<"$out")"

finish
