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

want='{"fresh":false,"base":"origin/main","behind":1,"ahead":1,"fetched":true}'

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
check "a behind branch not on origin keeps the verdict" "$want" "$(jq -c . <<<"$out")"
check "a behind branch not on origin is told to rebase" \
  "branch has not seen these commits on origin/main; rebase onto it and re-run:" \
  "$(head -1 "$tmp/err")"

g checkout -q --detach fix/local-2
"$base_fresh" >/dev/null 2>"$tmp/err"
check "a detached HEAD, whose push state is unknown, is told to merge the base in" \
  "branch has not seen these commits on origin/main; merge origin/main in, which keeps the next push a plain one, and re-run:" \
  "$(head -1 "$tmp/err")"

finish
