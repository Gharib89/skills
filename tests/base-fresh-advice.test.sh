#!/usr/bin/env bash
# base-fresh's advice on a behind branch: rebase only while the branch is not on
# origin. Once it is, a rebase rewrites published commits and the plain push
# `open-pr` makes is refused non-fast-forward, so the advice is to merge the
# base in. Driven end to end over a throwaway bare origin under the OS temp dir.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
base_fresh="$PWD/skills/ship/scripts/base-fresh.sh"

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
{
  g init -q --bare "$tmp/origin.git"
  g clone -q "$tmp/origin.git" "$tmp/w"
  cd "$tmp/w"
  g commit -q --allow-empty -m init && g push -q origin main
  git remote set-head origin main
  g checkout -q -b fix/pushed-1 && g commit -q --allow-empty -m a && g push -q -u origin fix/pushed-1
  g checkout -q -b fix/local-2 main && g commit -q --allow-empty -m b
  g checkout -q main && g commit -q --allow-empty -m c && g push -q origin main
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }

want='{"fresh":false,"base":"origin/main","behind":1,"ahead":1,"fetched":true,"branch":"fix/pushed-1"}'

g checkout -q fix/pushed-1
out=$("$base_fresh" 2>"$tmp/err"); rc=$?
check_rc "a behind branch on origin exits behind" 1 "$rc"
check "a behind branch on origin keeps the verdict" "$want" "$(jq -c . <<<"$out")"
check "a behind branch on origin is told to merge the base in" \
  "branch has not seen these commits on origin/main; merge origin/main in, which keeps the next push a plain one, and re-run:" \
  "$(head -1 "$tmp/err")"

g checkout -q fix/local-2
out=$("$base_fresh" 2>"$tmp/err"); rc=$?
check_rc "a behind branch not on origin exits behind" 1 "$rc"
check "a behind branch not on origin keeps the verdict" "${want/fix\/pushed-1/fix\/local-2}" "$(jq -c . <<<"$out")"
check "a behind branch not on origin is told to rebase" \
  "branch has not seen these commits on origin/main; rebase onto it and re-run:" \
  "$(head -1 "$tmp/err")"

g checkout -q --detach fix/local-2
out=$("$base_fresh" 2>"$tmp/err")
check "a detached HEAD carries a null branch" '[true,null]' "$(jq -c '[has("branch"), .branch]' <<<"$out")"
check "a detached HEAD, whose push state is unknown, is told to merge the base in" \
  "branch has not seen these commits on origin/main; merge origin/main in, which keeps the next push a plain one, and re-run:" \
  "$(head -1 "$tmp/err")"

# On the default branch itself the check answers nothing useful (HEAD is the
# base, so it is always fresh): a run belongs in its worktree, so that is
# tooling, exit 2, with the instruction on stderr and on stdout.
g checkout -q main
out=$("$base_fresh" 2>"$tmp/err"); rc=$?
check_rc "on the default branch it is a tooling error" 2 "$rc"
check "stdout names the worktree" true "$(jq '.error | contains("run from the worktree")' <<<"$out")"
check "stderr says the same" 1 "$(grep -c 'run from the worktree' "$tmp/err")"

# The evidence on stderr honours the mechanics' 40-line cap however far behind the
# branch is: the header and the newest 39 commits. The verdict on stdout still
# carries the full count, since the cap trims the evidence and never the answer.
{
  cd "$tmp/w" && g checkout -q main
  for i in $(seq 1 45); do g commit -q --allow-empty -m "m$i"; done
  g push -q origin main
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
g checkout -q fix/local-2
out=$("$base_fresh" 2>"$tmp/err"); rc=$?
check_rc "a branch far behind still exits behind" 1 "$rc"
check "the JSON reports the full behind count" 46 "$(jq .behind <<<"$out")"
check "the stderr evidence is at most 40 lines" 40 "$(wc -l < "$tmp/err" | tr -d ' ')"
check "the newest commit is in the evidence" 1 "$(grep -c ' m45$' "$tmp/err")"
check "the oldest commit is not in the evidence" 0 "$(grep -c ' m1$' "$tmp/err")"

finish
