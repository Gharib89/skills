#!/usr/bin/env bash
# scripts/revert-red.sh: does a test go red when the fix under it is reverted?
# The seam is the script's CLI: `<test> <path>...` in, an exit code and one line
# out. Driven end to end against a fixture repo with a base, a fix and a test
# commit, whose `origin/HEAD` is set by hand so no remote is needed.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

script=$PWD/scripts/revert-red.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
# The script's temp worktree lands here, so a leftover is visible.
export TMPDIR=$T/tmp
mkdir "$TMPDIR"

repo=$T/repo
git init -q -b main "$repo"
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
git -C "$repo" config commit.gpgsign false

mkdir "$repo/tests"
echo 'answer() { echo 1; }' > "$repo/lib.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm base
git -C "$repo" update-ref refs/remotes/origin/main HEAD
git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# The fix: a changed file and a file the fix adds.
echo 'answer() { echo 2; }' > "$repo/lib.sh"
echo 'extra() { echo yes; }' > "$repo/extra.sh"
git -C "$repo" add -A && git -C "$repo" commit -qm fix

# Three tests: one red on a reverted lib.sh, one red on a reverted extra.sh, and
# one that never reads either.
cat > "$repo/tests/answer.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 2
source lib.sh
[ "$(answer)" = 2 ]
EOF
cat > "$repo/tests/extra.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 2
source extra.sh
[ "$(extra)" = yes ]
EOF
cat > "$repo/tests/unrelated.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 2
[ -f lib.sh ]
EOF
git -C "$repo" add -A && git -C "$repo" commit -qm test

# <args>...: the script's exit code, run from the fixture repo.
rc_of() { (cd "$repo" && bash "$script" "$@" >/dev/null 2>&1); printf '%s' "$?"; }
out_of() { (cd "$repo" && bash "$script" "$@" 2>/dev/null); }

# --- red is what the script is for -------------------------------------------

check_rc "a test that goes red on the revert exits 0" \
  0 "$(rc_of tests/answer.test.sh lib.sh)"
check "no temp directory remains after a red run" "" "$(ls -A "$TMPDIR")"
check_rc "a file the fix added is removed by the revert" \
  0 "$(rc_of tests/extra.test.sh extra.sh)"
check_rc "several paths are reverted together" \
  0 "$(rc_of tests/extra.test.sh lib.sh extra.sh)"
check_rc "a test that stays green on the revert exits 1" \
  1 "$(rc_of tests/unrelated.test.sh lib.sh)"
check "no temp directory remains after a green run" "" "$(ls -A "$TMPDIR")"
# Reverting the wrong file leaves the fix in place, so the test passes: that is
# the vacuous case the script exists to name.
check_rc "reverting a file the test does not depend on exits 1" \
  1 "$(rc_of tests/answer.test.sh extra.sh)"

check "a red test says so" \
  "revert-red: tests/answer.test.sh goes red with lib.sh reverted." \
  "$(out_of tests/answer.test.sh lib.sh)"
check "a green test names the vacuous test" \
  "revert-red: tests/unrelated.test.sh stays green with lib.sh reverted, so it does not prove the fix." \
  "$(out_of tests/unrelated.test.sh lib.sh)"

# --- it leaves nothing behind ------------------------------------------------

check "the fixture repo keeps its one worktree" \
  1 "$(git -C "$repo" worktree list | wc -l | tr -d ' ')"
check "the fixture's own tree is untouched" \
  "answer() { echo 2; }" "$(cat "$repo/lib.sh")"

# --- inputs that are not a verdict -------------------------------------------

# Exit 1 means the test proved nothing, so a malformed call must not share it.
check_rc "no arguments is a usage error" 2 "$(rc_of)"
check_rc "a test with no path is a usage error" 2 "$(rc_of tests/answer.test.sh)"
# A test file bash cannot open exits non-zero, which would read as red.
check_rc "a test missing at HEAD is refused, not read as red" \
  2 "$(rc_of tests/nope.test.sh lib.sh)"
# Reverting the test itself deletes or restores the very file bash then fails to
# open, which reads as red.
check_rc "the test named among its own paths is refused" \
  2 "$(rc_of tests/answer.test.sh tests/answer.test.sh)"
# A directory clears an existence check, and reverting it deletes nothing, so the
# test would stay green and read as the vacuous case.
check_rc "a directory among the paths is refused" \
  2 "$(rc_of tests/answer.test.sh tests)"
check_rc "a directory as the test is refused" 2 "$(rc_of tests lib.sh)"
# A mistyped path reverts nothing, so the test stays green and would read as
# the vacuous case.
check_rc "a path in neither the base nor HEAD is refused" \
  2 "$(rc_of tests/answer.test.sh lib.shh)"

# The base is the merge base with origin/HEAD, so no origin/HEAD is no base.
git -C "$repo" symbolic-ref --delete refs/remotes/origin/HEAD
check_rc "no origin/HEAD is tooling, not a verdict" \
  2 "$(rc_of tests/answer.test.sh lib.sh)"
check "the refused runs left no temp directory either" "" "$(ls -A "$TMPDIR")"

finish
