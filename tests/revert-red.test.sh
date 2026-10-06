#!/usr/bin/env bash
# skills/ship/scripts/revert-red.sh: does a test go red when the fix under it is
# reverted? The seam is the mechanic's CLI: `<test> <path>...` in, an exit code
# and one JSON verdict out. Driven end to end against a fixture repo with a base,
# a fix and a test commit, whose `origin/HEAD` is set by hand so no remote is
# needed. The fixture carries no tests/host-stub.sh: a consumer has none, and the
# mechanic brings its own host stubs.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

script=$PWD/skills/ship/scripts/revert-red.sh
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

# Four tests: one red on a reverted lib.sh, one red on a reverted extra.sh, one
# that calls a host, and one that never reads either file.
cat > "$repo/tests/answer.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 2
source lib.sh
[ "$(answer)" = 2 ] || { echo MARKER-FROM-THE-TEST; exit 1; }
EOF
cat > "$repo/tests/extra.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 2
source extra.sh
[ "$(extra)" = yes ]
EOF
cat > "$repo/tests/hostcall.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 2
gh api repos/x/y
source lib.sh
[ "$(answer)" = 2 ]
EOF
cat > "$repo/tests/unrelated.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 2
[ -f lib.sh ]
EOF
# Two more: a non-shell test, which bash reads as red whatever the fix does, and a
# shell test already red at HEAD, whose red says nothing about the reverted path.
echo 'def test_answer(): assert True' > "$repo/tests/answer_test.py"
cat > "$repo/tests/redhead.test.sh" <<'EOF2'
cd "$(dirname "$0")/.." || exit 2
echo MARKER-RED-AT-HEAD >&2
exit 1
EOF2
git -C "$repo" add -A && git -C "$repo" commit -qm test

# <args>...: the script's exit code, stdout, or stderr, run from the fixture repo.
rc_of() { (cd "$repo" && bash "$script" "$@" >/dev/null 2>&1); printf '%s' "$?"; }
out_of() { (cd "$repo" && bash "$script" "$@" 2>/dev/null); }
err_of() { (cd "$repo" && bash "$script" "$@" 2>&1 >/dev/null | cat); }

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

check "a red test says so in one JSON verdict" \
  '{"test":"tests/answer.test.sh","paths":["lib.sh"],"red":true}' \
  "$(out_of tests/answer.test.sh lib.sh | jq -c .)"
check "a verdict lists every path reverted, in order" \
  '{"test":"tests/extra.test.sh","paths":["lib.sh","extra.sh"],"red":true}' \
  "$(out_of tests/extra.test.sh lib.sh extra.sh | jq -c .)"
check "a green test says red false" \
  '{"test":"tests/unrelated.test.sh","paths":["lib.sh"],"red":false}' \
  "$(out_of tests/unrelated.test.sh lib.sh | jq -c .)"
check "a green test names the vacuous test on stderr" \
  "revert-red: tests/unrelated.test.sh stays green with lib.sh reverted, so it does not prove the fix." \
  "$(err_of tests/unrelated.test.sh lib.sh)"
check "a red run puts the test's own failure on stderr" \
  "MARKER-FROM-THE-TEST" "$(err_of tests/answer.test.sh lib.sh)"

# Red for the stub's sake is not red for the fix's: a reverted tree that reaches a
# host, as one that loses the Host fake would, is not a verdict.
check_rc "a reverted tree that calls a host is tooling, not red" \
  2 "$(rc_of tests/hostcall.test.sh lib.sh)"
check "and the call is named on stderr" \
  "    gh api repos/x/y" \
  "$(err_of tests/hostcall.test.sh lib.sh | grep '^    ')"
check "and as a JSON error with no verdict on stdout" \
  "true" "$(out_of tests/hostcall.test.sh lib.sh | jq -r 'has("error") and (has("red") | not)')"

# A failed read is never a verdict: bash running a non-shell test, or a test that
# is red before anything is reverted, reads red whatever the fix does.
check_rc "a non-shell test is refused, not read as red" \
  2 "$(rc_of tests/answer_test.py lib.sh)"
check "and the refusal names the .sh rule and the n/a escape" \
  "revert-red runs shell tests (a .sh file); for another runner revert the path by hand and record \`Reverted-fix: <test>: n/a: <reason>\`" \
  "$(out_of tests/answer_test.py lib.sh | jq -r .error)"
check_rc "a test red at HEAD is refused, not read as red" \
  2 "$(rc_of tests/redhead.test.sh lib.sh)"
check "and the error says a red with the fix reverted proves nothing" \
  "tests/redhead.test.sh is red at HEAD, so a red with the fix reverted proves nothing" \
  "$(out_of tests/redhead.test.sh lib.sh | jq -r .error)"
check "and the HEAD run's own output is the evidence on stderr" \
  "MARKER-RED-AT-HEAD" "$(err_of tests/redhead.test.sh lib.sh | grep MARKER)"
check "and no verdict is on stdout" \
  "true" "$(out_of tests/redhead.test.sh lib.sh | jq -r 'has("error") and (has("red") | not)')"

# The stubs are the mechanic's own: copied to a directory with no tests/ beside
# it, which is what a consumer's skills/ship/scripts is, it still stubs the host.
standalone=$T/consumer/skills/ship/scripts
mkdir -p "$standalone"
cp "$(dirname "$script")/revert-red.sh" "$(dirname "$script")/_lib.sh" "$standalone/"
check_rc "with no tests/host-stub.sh anywhere near it, a red test still exits 0" \
  0 "$(cd "$repo" && bash "$standalone/revert-red.sh" tests/answer.test.sh lib.sh >/dev/null 2>&1; printf '%s' "$?")"
check_rc "and a reverted tree that calls a host is still tooling" \
  2 "$(cd "$repo" && bash "$standalone/revert-red.sh" tests/hostcall.test.sh lib.sh >/dev/null 2>&1; printf '%s' "$?")"
check "and the call is still named" \
  "    gh api repos/x/y" \
  "$(cd "$repo" && bash "$standalone/revert-red.sh" tests/hostcall.test.sh lib.sh 2>&1 >/dev/null | grep '^    ')"

# --- it leaves nothing behind ------------------------------------------------

check "the fixture repo keeps its one worktree" \
  1 "$(git -C "$repo" worktree list | wc -l | tr -d ' ')"
check "the fixture's own tree is untouched" \
  "answer() { echo 2; }" "$(cat "$repo/lib.sh")"

# --- help and inputs that are not a verdict ----------------------------------

help=$(cd "$T" && bash "$script" --help 2>"$T/err"); rc=$?
check_rc "--help exits 0 from a directory that is no repository" 0 "$rc"
check "--help opens with the usage line" \
  "usage: revert-red <test> <path>..." "$(sed -n 1p <<<"$help")"
check "--help names its stdout fields next" "stdout:" "$(sed -n 2p <<<"$help" | cut -c1-7)"
check "--help writes nothing on stderr" "" "$(cat "$T/err")"

# Exit 1 means the test proved nothing, so a malformed call must not share it.
check_rc "no arguments is a usage error" 2 "$(rc_of)"
check "a bad call prints one JSON object carrying the usage line" \
  "usage: revert-red <test> <path>..." "$(out_of | jq -r .error)"
check "a flag where the test belongs is refused with the usage line" \
  "usage: revert-red <test> <path>..." "$(out_of --x lib.sh | jq -r .error)"
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

# `cd ""` succeeds, so a failed toplevel read used to fall through to the next
# guard and name the wrong cause.
check "outside a repository the cause is named" \
  "not inside a git repository" \
  "$(cd "$T" && bash "$script" tests/answer.test.sh lib.sh 2>&1 >/dev/null)"
check_rc "outside a repository is tooling" \
  2 "$(cd "$T" && bash "$script" tests/answer.test.sh lib.sh >/dev/null 2>&1; printf '%s' "$?")"

# The base is the merge base with origin/HEAD, so no origin/HEAD is no base.
git -C "$repo" symbolic-ref --delete refs/remotes/origin/HEAD
check_rc "no origin/HEAD is tooling, not a verdict" \
  2 "$(rc_of tests/answer.test.sh lib.sh)"
check "the refused runs left no temp directory either" "" "$(ls -A "$TMPDIR")"

finish
