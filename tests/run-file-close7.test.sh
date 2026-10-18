#!/usr/bin/env bash
# Split by behaviour from tests/run-file-gates.test.sh: close 7 and grade cases.
# The run-file mechanic's self-review gates: `close 4` refuses until the Run file
# carries the evidence the diff calls for, `close 7` until each reviewer has a
# stop reason and a round, and `grade` writes the run's grade. Driven over a
# fixture repo with an origin, so the diff is the real `git diff` against the
# real merge base, beside a `dropped-lines` stub that always reports a removed
# block, which close 4 leaves to the self-review.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/run-file-lib.sh

run_file_gates_setup

# One Run file per case, so a refusal's "changes nothing" is that file's bytes.
n=100
rf=""
# run4 carries a finished self-review loop, so each case reads only the evidence
# it names; run4bare carries none, for the loop's own cases.
run4bare() { n=$((n + 1)); rf=$(bash "$bin/run-file.sh" init "$n" --scratchpad "$tmp/sp" \
  --state 0=done --state 1=done --state 2=done --state 3=done --state 4=open | jq -r .run_file); }
run4() { run4bare; printf '%s\n' 'Round: self-review 1: clean' 'Stop: self-review: tree unchanged' >> "$rf"; }
run7() { n=$((n + 1)); rf=$(bash "$bin/run-file.sh" init "$n" --scratchpad "$tmp/sp" --reviewers "${1-copilot, claude}" \
  --state 0=done --state 1=done --state 2=done --state 3=done --state 4=done --state 5=done --state 6=done --state 7=open | jq -r .run_file); }
add() { printf '%s\n' "$@" >> "$rf"; }
# call <cwd> <args...>: sets out, err and status for one call.
call() { local d=$1; shift; out=$( cd "$d" && bash "$bin/run-file.sh" "$@" 2>"$tmp/err" ); status=$?; err=$(jq -r '.error // empty' <<<"$out" 2>/dev/null); }
close() { call "$work" close "$@" --file "$rf"; }
has() { case $2 in *"$1"*) echo yes ;; *) echo no ;; esac; }
# refused <case> <fragment>: the last call exited 1 with that fragment in its error,
# and the Run file is as it was before it.
refused() {
  check_rc "$1: exits 1" 1 "$status"
  check "$1: names it" yes "$(has "$2" "$err")"
  check "$1: the error is the one on stderr too" "$err" "$(cat "$tmp/err")"
  check "$1: leaves the record as it was" "$held" "$(cat "$rf")"
}
admitted() { check_rc "$1: exits ok" 0 "$status"; check "$1: closes the phase" completed "$(jq -r .mirror <<<"$out")"; }

# --- close 7 ---------------------------------------------------------------------

stops='cap, tree unchanged at <sha>, small lane, inline lane, auto-once, not landed, not reviewed, not invoked: <primary> reviewed'
run7; held=$(cat "$rf"); close 7
refused "phase 7 with no stop and no round" 'no Stop line for copilot: add `Stop: copilot: <cap|tree unchanged at <sha>|small lane|inline lane|auto-once|not landed|not reviewed|not invoked: <primary> reviewed>`'
check "the same refusal names the other reviewer's stop" yes "$(has 'no Stop line for claude' "$err")"
check "and each reviewer's missing round" yes "$(has 'no Round line for copilot: add `Round: copilot <n>: <text>`, one per round, unless it stopped `not reviewed`, `not invoked: <primary> reviewed` or `inline lane`' "$err")"
check "and the other's" yes "$(has 'no Round line for claude' "$err")"

run7; add 'Stop: copilot: cap' 'Stop: claude: auto-once' 'Round: copilot 1: 2 findings, both fixed' 'Round: copilot 2: clean' 'Round: claude 1: clean'
close 7
admitted "a stop and a round for each reviewer"

run7; add 'Stop: copilot: not reviewed' 'Stop: claude: small lane' 'Round: claude 1: clean'
close 7
admitted "a not-reviewed reviewer needs no round"

run7; add 'Stop: copilot: inline lane' 'Stop: claude: inline lane'
close 7
admitted "an inline-lane reviewer needs no round"

run7; add '- Stop: copilot: tree unchanged at 0123abc' '- Round: copilot 1: clean' 'Stop: claude: not reviewed'
close 7
admitted "bulleted stop and round lines"

run7; add 'Stop: copilot: cap' 'Stop: claude: not reviewed' 'Round: copilot 1: clean'; close 7
admitted "one reviewer with rounds and one not reviewed"

# `not reviewed: <reason>` is the documented spelling of `not reviewed` (#787):
# the reason rides along and the stop reads the same, a round still not owed.
run7; add 'Stop: copilot: not reviewed: unreachable' 'Stop: claude: small lane' 'Round: claude 1: clean'
close 7
admitted "a not-reviewed stop carrying its reason needs no round"
run7; add 'Round: copilot 1: clean' 'Stop: copilot: not reviewed: threads unreadable' 'Stop: claude: not invoked: copilot reviewed'; held=$(cat "$rf"); close 7
refused "a not-invoked fallback whose primary stopped on a not-reviewed reason" "Stop line for claude says copilot reviewed, but copilot stopped 'not reviewed: threads unreadable'"
run7; add 'Stop: copilot: not reviewedish' 'Stop: claude: small lane' 'Round: claude 1: clean'; held=$(cat "$rf"); close 7
refused "a longer word is no not-reviewed reason" "Stop line for copilot has reason 'not reviewedish'"

# A fallback whose primary reviewed was never invoked: its stop says so, with no
# round (#672). `not reviewed` with no round is a round that never landed; with
# one, a round that landed whose threads could not be read.
run7; add 'Round: copilot 1: 2 findings, both fixed' 'Stop: copilot: auto-once' 'Stop: claude: not invoked: copilot reviewed'; close 7
admitted "a fallback never invoked: its Stop line alone, the primary's round and auto-once"
run7 'Codex, Claude Code'; add 'Round: Codex 1: clean' 'Stop: Codex: tree unchanged at 0123abc' 'Stop: Claude Code: not invoked: Codex reviewed'; close 7
admitted "a not-invoked fallback whose name has a space"
run7; add 'Round: copilot 1: clean' 'Stop: copilot: cap' 'Stop: claude: not invoked: copilot'; held=$(cat "$rf"); close 7
refused "a not-invoked stop that names no reviewed primary" "Stop line for claude has reason 'not invoked: copilot'"
# The named primary must be on the row and have stopped on a reviewed stop.
for p in 'not reviewed' 'not landed' 'inline lane'; do
  run7; add 'Round: copilot 1: clean' "Stop: copilot: $p" 'Stop: claude: not invoked: copilot reviewed'; held=$(cat "$rf"); close 7
  refused "a not-invoked fallback whose primary stopped $p" "Stop line for claude says copilot reviewed, but copilot stopped '$p'"
done
run7; add 'Round: copilot 1: clean' 'Stop: copilot: cap' 'Stop: claude: not invoked: codex reviewed'; held=$(cat "$rf"); close 7
refused "a not-invoked fallback naming a reviewer off the row" "Stop line for claude names codex, which is not a reviewer on the phase 7 row"
run7; add 'Round: copilot 1: clean' 'Stop: copilot: cap' 'Round: claude 1: landed, threads unreadable' 'Stop: claude: not reviewed'; close 7
admitted "a Round line beside Stop: not reviewed, a round that landed with unreadable threads"

# `not landed`: a round was dispositioned, then a later one did not land (#551).
run7; add 'Round: copilot 1: 1 finding, fixed' 'Stop: copilot: not landed' 'Stop: claude: not reviewed'; close 7
admitted "a not-landed reviewer with its dispositioned round"
run7; add 'Stop: copilot: not landed' 'Stop: claude: not reviewed'; held=$(cat "$rf"); close 7
refused "a not-landed reviewer with no round" 'no Round line for copilot'

run7; add 'Stop: copilot: cap' 'Stop: claude: not reviewed'; held=$(cat "$rf"); close 7
refused "a stopped reviewer with no round" 'no Round line for copilot'
check "the not-reviewed reviewer is not asked for a round" no "$(has 'no Round line for claude' "$err")"
check "no Stop is asked for" no "$(has 'no Stop line' "$err")"

run7; add 'Stop: copilot: cap' 'Stop: claude: whenever' 'Round: copilot 1: x' 'Round: claude 1: x'; held=$(cat "$rf"); close 7
refused "a stop reason outside the list" "Stop line for claude has reason 'whenever', which is not one of $stops"
check "the valid one is left alone" no "$(has 'copilot' "$err")"

# An unchanged tree settles a reviewer, so it names the head the round read.
run7; add 'Round: copilot 1: clean' 'Stop: copilot: tree unchanged' 'Stop: claude: not reviewed'; held=$(cat "$rf"); close 7
refused "a tree-unchanged stop with no head" 'Stop line for copilot has no head: write `Stop: copilot: tree unchanged at <sha>`, the head read-pr returned for the round'
run7; add 'Round: copilot 1: clean' 'Stop: copilot: tree unchanged at HEAD' 'Stop: claude: not reviewed'; held=$(cat "$rf"); close 7
refused "a tree-unchanged stop whose head is no sha" "Stop line for copilot has reason 'tree unchanged at HEAD', whose head is not a commit sha"

run7; add 'Stop: copilot: cap: blocked' 'Stop: claude: cap' 'Round: claude 1: x'; held=$(cat "$rf"); close 7
refused "a reason that only starts with a listed one" "Stop line for copilot has reason 'cap: blocked'"

run7; add 'Stop: copilot: cap' 'Stop: claude: cap' 'Stop: claude: nonsense' 'Round: copilot 1: x' 'Round: claude 1: x'; held=$(cat "$rf"); close 7
refused "the last Stop line decides" "Stop line for claude has reason 'nonsense'"
run7; add 'Stop: copilot: cap' 'Stop: claude: nonsense' 'Stop: claude: cap' 'Round: copilot 1: x' 'Round: claude 1: x'; close 7
admitted "a later valid Stop line replaces an earlier invalid one"

for bad in 'Round: copilot x: text' 'Round: copilot 0: text' 'Round: copilot 1:' 'Round: copilot 1: ' 'Round: copilot: text' 'Round: copilot 01: text' 'Round: copilots 1: text' 'Round: copilot 1 text'; do
  run7; add 'Stop: copilot: cap' 'Stop: claude: not reviewed' "$bad"; held=$(cat "$rf"); close 7
  refused "the round line '$bad'" 'no Round line for copilot'
done

# A name may hold spaces, dots and hyphens: matched by exact prefix, never as a pattern.
run7 'my.rev-1, Code Rabbit, claude'
add 'Stop: my.rev-1: cap' 'Round: my.rev-1 1: x' 'Stop: Code Rabbit: cap' 'Round: Code Rabbit 1: x' 'Stop: claude: cap' 'Round: claude 1: x'
close 7
admitted "reviewer names with a dot, a hyphen and a space"
run7 'my.rev-1, Code Rabbit, claude'
add 'Stop: myXrev-1: cap' 'Round: myXrev-1 1: x' 'Stop: Code Rabbit: cap' 'Round: Code Rabbit 1: x' 'Stop: claude: cap' 'Round: claude 1: x'
held=$(cat "$rf"); close 7
refused "a name's dot is not a wildcard" 'no Stop line for my.rev-1'
run7 'claude, claude code'
add 'Stop: claude code: cap' 'Round: claude code 1: x' 'Stop: claude: cap'
held=$(cat "$rf"); close 7
refused "a round of 'claude code' is not a round of 'claude'" 'no Round line for claude: add'
check "the longer name has its own" no "$(has 'no Round line for claude code' "$err")"

# No reviewer, or a list that is not names, has nothing to hold the check to.
run7 none; close 7
admitted "no reviewers named"
run7 'None.'; close 7
admitted "None. as the reviewers"
run7 'copilot (on-request), claude'; close 7
admitted "a list that is not name-shaped skips the check"

# --- grade -----------------------------------------------------------------------

run4
call "$work" grade minor --file "$rf"
check_rc "grade exits ok" 0 "$status"
check "grade answers the file and the word" "$(jq -nc --arg f "$rf" '{run_file: $f, grade: "minor"}')" "$(jq -c . <<<"$out")"
check "grade creates the section with the line" '## Grade

Grade: minor' "$(sed -n '/^## Grade$/,$p' "$rf")"
call "$work" grade breaking --file "$rf"
check "a second grade replaces the first" 'Grade: breaking' "$(grep '^Grade: ' "$rf")"
check "and leaves one" 1 "$(grep -c '^Grade: ' "$rf")"
check "and one section" 1 "$(grep -c '^## Grade$' "$rf")"

# A section the run already holds, with another below it: the line stays in it.
run4; printf '\n## Grade\n\nGrade: patch\nwhy: a typo\n\n## Notes\n\nGrade: not this one\n' >> "$rf"
call "$work" grade minor --file "$rf"
check "grade replaces the line in its own section" 'Grade: minor
why: a typo' "$(sed -n '/^## Grade$/,/^## Notes$/p' "$rf" | grep -v '^$' | grep -v '^## ')"
check "and leaves a Grade line elsewhere alone" 'Grade: not this one' "$(grep 'not this one' "$rf")"
# The reader (ship_recorded_grade) and this writer take one shape: an optional "- "
# before the line and trailing blanks after the heading.
run4; printf '\n## Grade \n\n- Grade: patch\n\n## Notes\n' >> "$rf"
call "$work" grade minor --file "$rf"
check "grade replaces a bulleted line under a heading with trailing blanks" 'Grade: minor' "$(grep 'Grade: ' "$rf")"
check "and adds no second heading" 1 "$(grep -c '^## Grade' "$rf")"
run4; printf '\n## Grade \n\nnone yet\n\n## Notes\n' >> "$rf"
call "$work" grade minor --file "$rf"
check "grade writes under a heading with trailing blanks, not a new section" 1 "$(grep -c '^## Grade' "$rf")"

run4; printf '\n## Grade\n\nnone yet\n\n## Notes\n\nx\n' >> "$rf"
call "$work" grade patch --file "$rf"
check "grade writes into an empty section, above the next" '## Grade

none yet
Grade: patch

## Notes' "$(sed -n '/^## Grade$/,/^## Notes$/p' "$rf")"

run4; held=$(cat "$rf")
for w in major Patch '' ; do
  call "$work" grade "$w" --file "$rf"
  check_rc "grade '$w' is malformed" 2 "$status"
  check "grade '$w' prints the usage line" yes "$(has 'grade <patch|minor|breaking>' "$err")"
done
call "$work" grade --file "$rf"
check_rc "grade with no word is malformed" 2 "$status"
call "$work" grade patch
check_rc "grade with no record named is malformed" 2 "$status"
check "a refused grade changes nothing" "$held" "$(cat "$rf")"
call "$work" grade patch --file "$tmp/no-such.md"
check_rc "grade on a Run file that is not there exits 1" 1 "$status"

finish
