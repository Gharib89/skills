#!/usr/bin/env bash
# skills/ship/scripts/run-file.sh `prove`: the red line a test earns by going red
# with its fix reverted is written by the mechanic that ran the revert, never by
# hand. The seam is `run-file prove <test> <path>... --file <run file>`: an exit
# code, one JSON answer, and the Run file's bytes. Driven end to end over a copy
# of the mechanic beside its real sibling `revert-red`, against a fixture repo
# with a base, a fix and a test commit whose `origin/HEAD` is set by hand.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
bin=$T/bin repo=$T/repo
mkdir -p "$bin"
cp skills/ship/scripts/run-file.sh skills/ship/scripts/revert-red.sh skills/ship/scripts/_lib.sh "$bin/"

git init -q -b main "$repo"
g() { git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
mkdir "$repo/tests"
echo 'answer() { echo 1; }' > "$repo/lib.sh"
echo 'other() { echo 1; }' > "$repo/other.sh"
g add -A && g commit -qm base
g update-ref refs/remotes/origin/main HEAD
g symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
echo 'answer() { echo 2; }' > "$repo/lib.sh"
g add -A && g commit -qm fix
cat > "$repo/tests/answer.test.sh" <<'EOF'
cd "$(dirname "$0")/.." || exit 2
source lib.sh
[ "$(answer)" = 2 ]
EOF
g add -A && g commit -qm test
head=$(g rev-parse HEAD)

rf=$(cd "$repo" && bash "$bin/run-file.sh" init 7 --scratchpad "$T/sp" --state 4=open | jq -r .run_file)
# prove <args>... [-- <command>...]: sets out and status for one call from the
# fixture repo, its --file placed before any command.
prove() {
  local a=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do a+=("$1"); shift; done
  out=$(cd "$repo" && bash "$bin/run-file.sh" prove "${a[@]}" --file "$rf" "$@" 2>"$T/err"); status=$?
  err=$(jq -r '.error // empty' <<<"$out" 2>/dev/null)
}

# --- red: the line is written, and the answer carries the verdict ------------------

prove tests/answer.test.sh lib.sh
check_rc "a test that goes red with its fix reverted exits 0" 0 "$status"
check "the answer is revert-red's verdict plus the record and the head" \
  "{\"test\":\"tests/answer.test.sh\",\"paths\":[\"lib.sh\"],\"red\":true,\"command\":[\"bash\",\"tests/answer.test.sh\"],\"run_file\":\"$rf\",\"head\":\"$head\"}" \
  "$(jq -c . <<<"$out")"
check "the red line lands under ## Evidence, naming the head and the reverted paths" \
  "## Evidence

Reverted-fix: tests/answer.test.sh: red at $head reverting lib.sh" \
  "$(sed -n '/^## Evidence$/,$p' "$rf")"

prove tests/answer.test.sh lib.sh other.sh
check_rc "several reverted paths exit 0" 0 "$status"
check "a second line follows the first, its paths space-separated in order" \
  "Reverted-fix: tests/answer.test.sh: red at $head reverting lib.sh other.sh" \
  "$(tail -n 1 "$rf")"

# --- green and tooling: nothing is written, revert-red's exit is the answer --------

held=$(cat "$rf")
prove tests/answer.test.sh other.sh
check_rc "a test that stays green exits 1, revert-red's code" 1 "$status"
check "a green run answers revert-red's verdict" false "$(jq -r .red <<<"$out")"
check "a green run writes nothing" "$held" "$(cat "$rf")"

prove tests/missing.test.sh lib.sh
check_rc "a test revert-red cannot run exits 2" 2 "$status"
check "a tooling refusal carries revert-red's own error" \
  "tests/missing.test.sh is not a file committed at HEAD" "$(jq -r .error <<<"$out")"
check "a tooling refusal writes nothing" "$held" "$(cat "$rf")"

# --- the call itself -----------------------------------------------------------------

prove tests/answer.test.sh
check_rc "a test with no path to revert is a usage error" 2 "$status"
check "a test with no path answers the usage line" "$(bash "$bin/run-file.sh" --help | head -n 1)" "$err"
check "--help states prove's verbatim-word rule" "1" \
  "$(bash "$bin/run-file.sh" --help | tr '\n' ' ' | grep -c '<test> must be one of the words of *<command>, character for character, or a node ID under it (<test>::<name>)')"
prove tests/answer.test.sh 'lib .sh'
check_rc "a reverted path holding whitespace is refused: the line could not be read back" 2 "$status"
check "the whitespace refusal says why" \
  "prove cannot record 'lib .sh': a reverted path holding whitespace cannot be read back from its line" "$err"
check "the whitespace refusal writes nothing" "$held" "$(cat "$rf")"
out=$(cd "$repo" && bash "$bin/run-file.sh" prove tests/answer.test.sh lib.sh --file "$T/none.md" 2>/dev/null); status=$?
check_rc "a missing Run file is refused before revert-red runs" 1 "$status"
check "the refusal names the missing record, not a revert-red answer" yes \
  "$(case $(jq -r .error <<<"$out") in "no Run file at $T/none.md"*) echo yes ;; *) echo no ;; esac)"

# --- the line is one close 4 reads -------------------------------------------------

# A fix in a file whose name git reads as pathspec magic unless it is written `./`.
echo 'colon() { echo yes; }' > "$repo/:fix.sh"
printf '%s\n' 'cd "$(dirname "$0")/.." || exit 2' 'source ./:fix.sh' '[ "$(colon)" = yes ]' > "$repo/tests/colon.test.sh"
g add -A && g commit -qm 'colon fix and test'
head=$(g rev-parse HEAD)

rf=$(cd "$repo" && bash "$bin/run-file.sh" init 8 --scratchpad "$T/sp" --state 4=open | jq -r .run_file)
prove tests/colon.test.sh ./:fix.sh
check_rc "a path kept literal by its ./ reaches revert-red as typed" 0 "$status"
check "and is recorded without it" "Reverted-fix: tests/colon.test.sh: red at $head reverting :fix.sh" "$(tail -n 1 "$rf")"
prove ./tests/answer.test.sh ././lib.sh
check_rc "paths typed with a leading ./ prove as any other" 0 "$status"
check "the line names them as git diff prints them, top-relative with no ./" \
  "Reverted-fix: tests/answer.test.sh: red at $head reverting lib.sh" "$(tail -n 1 "$rf")"
# The paths are read back literally: an edit to :fix.sh makes its line stale.
echo 'colon() { echo edited; }' > "$repo/:fix.sh"
out=$(cd "$repo" && bash "$bin/run-file.sh" close 4 --file "$rf" 2>/dev/null); status=$?
check_rc "an edit to a pathspec-magic name since the head is refused" 1 "$status"
check "as a stale line" yes "$(case $(jq -r .error <<<"$out") in *"Reverted-fix line for tests/colon.test.sh is stale"*) echo yes ;; *) echo no ;; esac)"
g checkout -q -- ':(literal):fix.sh'
printf '%s\n' 'Round: self-review 1: clean' 'Stop: self-review: tree unchanged' >> "$rf"
out=$(cd "$repo" && bash "$bin/run-file.sh" close 4 --file "$rf" 2>&1); status=$?
check_rc "close 4 accepts each line prove wrote for a test the diff adds, a pathspec-magic name included" 0 "$status"

# --- another runner's test, through its command after -- ------------------------

# python3 stands in for pytest: the command runs as argv at the tree's top.
printf '%s\n' 'import sys' "sys.exit(0 if 'echo 2' in open('lib.sh').read() else 1)" > "$repo/tests/answer_check.py"
g add -A && g commit -qm 'python test'
head=$(g rev-parse HEAD)
# A record of its own, holding a line for each shell test the diff adds, so the
# close 4 below has only the command's line left to judge.
rf=$(cd "$repo" && bash "$bin/run-file.sh" init 9 --scratchpad "$T/sp" --state 4=open | jq -r .run_file)
prove tests/answer.test.sh lib.sh
prove tests/colon.test.sh ./:fix.sh
prove tests/answer_check.py lib.sh -- python3 tests/answer_check.py
check_rc "a non-shell test run by its command goes red and exits 0" 0 "$status"
check "the answer carries the command beside the verdict" \
  "{\"test\":\"tests/answer_check.py\",\"paths\":[\"lib.sh\"],\"red\":true,\"command\":[\"python3\",\"tests/answer_check.py\"],\"run_file\":\"$rf\",\"head\":\"$head\"}" \
  "$(jq -c . <<<"$out")"
check "the line keeps its shape, the command left out of it" \
  "Reverted-fix: tests/answer_check.py: red at $head reverting lib.sh" "$(tail -n 1 "$rf")"
held=$(cat "$rf")
prove tests/answer_check.py other.sh -- python3 tests/answer_check.py
check_rc "a command that stays green exits 1" 1 "$status"
prove tests/answer_check.py lib.sh -- python3 tests/other_check.py
check_rc "a command that does not name the test exits 2" 2 "$status"
prove tests/answer_check.py lib.sh
check_rc "a non-shell test with no command is still refused" 2 "$status"
check "and the refusal names the -- form" yes "$(case $err in *'-- <command>...'*) echo yes ;; *) echo no ;; esac)"
check "none of them writes a line" "$held" "$(cat "$rf")"
out=$(cd "$repo" && bash "$bin/run-file.sh" prove tests/answer_check.py lib.sh --file "$rf" -- 2>/dev/null); status=$?
check_rc "a -- with no command is a usage error" 2 "$status"
printf '%s\n' 'Round: self-review 1: clean' 'Stop: self-review: tree unchanged' >> "$rf"
out=$(cd "$repo" && bash "$bin/run-file.sh" close 4 --file "$rf" 2>&1); status=$?
check_rc "close 4 accepts the line a command's red wrote" 0 "$status"

finish
