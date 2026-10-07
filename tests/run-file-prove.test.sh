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
cp skills/ship/scripts/run-file.sh skills/ship/scripts/revert-red.sh skills/ship/scripts/dropped-lines.sh skills/ship/scripts/_lib.sh "$bin/"

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
# prove <args>...: sets out and status for one call from the fixture repo.
prove() { out=$(cd "$repo" && bash "$bin/run-file.sh" prove "$@" --file "$rf" 2>"$T/err"); status=$?; err=$(jq -r '.error // empty' <<<"$out" 2>/dev/null); }

# --- red: the line is written, and the answer carries the verdict ------------------

prove tests/answer.test.sh lib.sh
check_rc "a test that goes red with its fix reverted exits 0" 0 "$status"
check "the answer is revert-red's verdict plus the record and the head" \
  "{\"test\":\"tests/answer.test.sh\",\"paths\":[\"lib.sh\"],\"red\":true,\"run_file\":\"$rf\",\"head\":\"$head\"}" \
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

rf=$(cd "$repo" && bash "$bin/run-file.sh" init 8 --scratchpad "$T/sp" --state 4=open | jq -r .run_file)
prove ./tests/answer.test.sh ././lib.sh
check_rc "paths typed with a leading ./ prove as any other" 0 "$status"
check "the line names them as git diff prints them, top-relative with no ./" \
  "Reverted-fix: tests/answer.test.sh: red at $head reverting lib.sh" "$(tail -n 1 "$rf")"
out=$(cd "$repo" && bash "$bin/run-file.sh" close 4 --file "$rf" 2>&1); status=$?
check_rc "close 4 accepts the line prove wrote for the test the diff adds" 0 "$status"

finish
