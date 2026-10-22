#!/usr/bin/env bash
# skills/ship/scripts/revert-red.sh `--fix <commit>`: a review fix is judged against
# the tree before it, not the merge base, and a red that is only a missing file the
# fix added is no proof (#933). Driven against a fixture repo whose `origin/HEAD` is
# set by hand; tests/revert-red.test.sh holds the rest of the mechanic's cases.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

script=$PWD/skills/ship/scripts/revert-red.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export TMPDIR=$T/tmp
mkdir "$TMPDIR"

# --- --fix: a review fix is judged against its own parent (#933) ---------------

# Two fix commits touch one file. Reverted to the merge base, a test of the
# first fix goes red on the second's revert too; reverted to the second fix's
# parent, each is judged alone.
multi=$T/multi
git init -q -b main "$multi"
git -C "$multi" config user.email t@example.com
git -C "$multi" config user.name t
git -C "$multi" config commit.gpgsign false
mkdir "$multi/tests"
echo 'answer() { echo 1; }' > "$multi/lib.sh"
git -C "$multi" add -A && git -C "$multi" commit -qm base
git -C "$multi" update-ref refs/remotes/origin/main HEAD
git -C "$multi" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
printf '%s\n' 'answer() { echo 2; }' > "$multi/lib.sh"
git -C "$multi" add -A && git -C "$multi" commit -qm 'fix one'
fix1=$(git -C "$multi" rev-parse HEAD)
printf '%s\n' 'answer() { echo 2; }' 'other() { echo yes; }' > "$multi/lib.sh"
git -C "$multi" add -A && git -C "$multi" commit -qm 'fix two'
fix2=$(git -C "$multi" rev-parse HEAD)
printf '%s\n' 'cd "$(dirname "$0")/.." || exit 2' 'source lib.sh' '[ "$(answer)" = 2 ]' > "$multi/tests/one.test.sh"
printf '%s\n' 'cd "$(dirname "$0")/.." || exit 2' 'source lib.sh' '[ "$(other)" = yes ]' > "$multi/tests/two.test.sh"
printf '%s\n' 'newfn() { echo n; }' > "$multi/added.sh"
printf '%s\n' 'cd "$(dirname "$0")/.." || exit 2' 'source added.sh' '[ "$(newfn)" = n ]' > "$multi/tests/added.test.sh"
git -C "$multi" add -A && git -C "$multi" commit -qm tests
multi_rc() { (cd "$multi" && bash "$script" "$@" >/dev/null 2>&1); printf '%s' "$?"; }
multi_err() { (cd "$multi" && bash "$script" "$@" 2>&1 >/dev/null | cat); }
check_rc "without --fix the first fix's test goes red on the whole branch's revert" 0 "$(multi_rc tests/one.test.sh lib.sh)"
check_rc "--fix names the second fix: the first fix's test stays green, so it does not prove it" \
  1 "$(multi_rc tests/one.test.sh lib.sh --fix "$fix2")"
check_rc "--fix names the second fix: its own test goes red" 0 "$(multi_rc tests/two.test.sh lib.sh --fix "$fix2")"
check_rc "--fix names the first fix: its own test goes red" 0 "$(multi_rc tests/one.test.sh lib.sh --fix "$fix1")"
check "a --fix verdict names the fix" \
  "{\"test\":\"tests/two.test.sh\",\"paths\":[\"lib.sh\"],\"red\":true,\"command\":[\"bash\",\"tests/two.test.sh\"],\"fix\":\"$fix2\"}" \
  "$(cd "$multi" && bash "$script" tests/two.test.sh lib.sh --fix "$fix2" 2>/dev/null | jq -c .)"
check "a green --fix run names the fix on stderr" \
  "revert-red: tests/one.test.sh stays green with lib.sh reverted to ${fix2:0:12}^, so it does not prove that fix." \
  "$(multi_err tests/one.test.sh lib.sh --fix "$fix2")"
check_rc "--fix with a revision no commit answers to is tooling" 2 "$(multi_rc tests/one.test.sh lib.sh --fix nope)"
check_rc "--fix with no value is tooling" 2 "$(multi_rc tests/one.test.sh lib.sh --fix)"
check_rc "a path in neither the fix's parent nor HEAD is refused" 2 "$(multi_rc tests/one.test.sh nothere.sh --fix "$fix2")"
check_rc "a --fix that is not on HEAD's history is tooling" 2 "$(multi_rc tests/one.test.sh lib.sh --fix "$(git -C "$multi" commit-tree -m x "$(git -C "$multi" write-tree)")")"
check_rc "a file the fix added is still a missing-file red" 1 "$(multi_rc tests/added.test.sh added.sh)"

finish
