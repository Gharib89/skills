#!/usr/bin/env bash
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

# --- close 4: Reverted-fix ------------------------------------------------------

run4; held=$(cat "$rf")
close 4
admitted "a diff with nothing in it closes with no evidence"

prove_hint='run `run-file prove tests/new.test.sh <path>...` or add `Reverted-fix: tests/new.test.sh: n/a: <reason>`'
reset; put tests/new.test.sh 'echo new'
run4; held=$(cat "$rf"); close 4
refused "an added test file with no Reverted-fix line" "no Reverted-fix line for tests/new.test.sh: $prove_hint"
check "close 4 names the phase it refused" "phase 4 cannot close: no Reverted-fix line for tests/new.test.sh: $prove_hint" "$err"

# A red line is the one `run-file prove` writes: the head revert-red ran on and
# the paths it reverted, read back against the working tree.
reset; put tests/new.test.sh 'echo new'; put src/x.txt 'fixed'; g add -A; g commit -q -m 'test and fix'
at=$(g rev-parse HEAD)
run4; add "Reverted-fix: tests/new.test.sh: red at $at reverting src/x.txt"; close 4
admitted "a produced red line for the added test file"
run4; add "- Reverted-fix: tests/new.test.sh: red at ${at:0:12} reverting src/x.txt keep.txt"; close 4
admitted "a bulleted red line at an abbreviated head, reverting two paths"

put notes.txt 'a later change touching neither'; g add -A; g commit -q -m later
run4; add "Reverted-fix: tests/new.test.sh: red at $at reverting src/x.txt"; close 4
admitted "a later commit touching neither the test nor a reverted path keeps the line"

stale_hint="re-run \`run-file prove tests/new.test.sh <path>...\`"
put tests/new.test.sh 'echo edited'
run4; add "Reverted-fix: tests/new.test.sh: red at $at reverting src/x.txt"; held=$(cat "$rf"); close 4
refused "a red line whose test changed in the working tree since its head" \
  "Reverted-fix line for tests/new.test.sh is stale: the test or a path it reverted changed since $at: $stale_hint"
g checkout -q -- tests/new.test.sh
put src/x.txt 'fixed again'; g add -A; g commit -q -m 'fix again'
run4; add "Reverted-fix: tests/new.test.sh: red at $at reverting src/x.txt"; held=$(cat "$rf"); close 4
refused "a red line whose reverted path changed in a later commit" 'Reverted-fix line for tests/new.test.sh is stale'
run4; add "Reverted-fix: tests/new.test.sh: red at $at reverting keep.txt"; close 4
admitted "a line reverting another path that is unchanged since its head"
put src/new.txt 'untracked'
run4; add "Reverted-fix: tests/new.test.sh: red at $at reverting src/new.txt"; held=$(cat "$rf"); close 4
refused "a reverted path untracked in the working tree, absent at its head" 'Reverted-fix line for tests/new.test.sh is stale'
rm "$work/src/new.txt"
run4; add 'Reverted-fix: tests/new.test.sh: red at 0123456789abcdef reverting src/x.txt'; held=$(cat "$rf"); close 4
refused "a red line naming a head that is no commit here" \
  'Reverted-fix line for tests/new.test.sh names 0123456789abcdef, which is no commit here: run `run-file prove tests/new.test.sh <path>...`'

# The hand-written shapes the earlier version accepted are each refused, naming prove.
old_hint='Reverted-fix line for tests/new.test.sh is hand-written: run `run-file prove tests/new.test.sh <path>...`, which writes `red at <sha> reverting <path>...`'
for line in 'red' 'red: went red with lib.sh reverted' "red at $at" "red at $at reverting " "red at nothex reverting src/x.txt"; do
  run4; add "Reverted-fix: tests/new.test.sh: $line"; held=$(cat "$rf"); close 4
  refused "the hand-written red line '$line'" "$old_hint"
done
reset

reset; put tests/new.test.sh 'echo new'
run4; add '- Reverted-fix: tests/new.test.sh: n/a: pure docs fixture'; close 4
admitted "a bulleted n/a line with a reason"

# A validator gets a negative control: each of these must be refused.
run4; add 'Reverted-fix: tests/new.test.sh: n/a:'; held=$(cat "$rf"); close 4
refused "an n/a line with no reason" 'no Reverted-fix line for tests/new.test.sh'
run4; add 'Reverted-fix: tests/new.test.sh: n/a:   '; held=$(cat "$rf"); close 4
refused "an n/a line with a blank reason" 'no Reverted-fix line for tests/new.test.sh'
run4; add 'Reverted-fix: tests/new.test.sh: maybe'; held=$(cat "$rf"); close 4
refused "a Reverted-fix word outside red and n/a" 'no Reverted-fix line for tests/new.test.sh'
run4; add 'Reverted-fix: tests/other.test.sh: n/a: elsewhere'; held=$(cat "$rf"); close 4
refused "a Reverted-fix line for another test file" 'no Reverted-fix line for tests/new.test.sh'
run4; add '  Reverted-fix: tests/new.test.sh: n/a: indented'; held=$(cat "$rf"); close 4
refused "an indented Reverted-fix line (matched at line start)" 'no Reverted-fix line for tests/new.test.sh'

# What counts as a test file, and as a change.
reset; put tests/old.test.sh 'echo changed'
run4; held=$(cat "$rf"); close 4
refused "a modified tracked test file" 'no Reverted-fix line for tests/old.test.sh'

reset; rm "$work/tests/old.test.sh"
run4; close 4
admitted "a deleted test file needs no line"

reset; put src/x.txt 'changed'; put src/y.sh 'echo y'
run4; close 4
admitted "a changed non-test file needs no Reverted-fix line"

reset; put src/foo_test.go 'x'; put pkg/test_thing.py 'x'; put web/__tests__/a.js 'x'; put a/test/b.txt 'x'; put c/d.spec.ts 'x'; put e/tests/f.txt 'x'
run4; held=$(cat "$rf"); close 4
for p in src/foo_test.go pkg/test_thing.py web/__tests__/a.js a/test/b.txt c/d.spec.ts e/tests/f.txt; do
  check "test path $p is held to a Reverted-fix line" yes "$(has "no Reverted-fix line for $p:" "$err")"
done
check_rc "every test-shaped path is refused together" 1 "$status"

reset; put src/contest.txt 'x'; put src/latest.sh 'echo x'; put docs/testing-notes.md 'x'
run4; close 4
admitted "paths that merely contain the letters test are not test files"

reset; put tests/new.test.sh 'echo new'; g add tests/new.test.sh; g commit -q -m 'add a test'
run4; held=$(cat "$rf"); close 4
refused "a test file committed on the branch" 'no Reverted-fix line for tests/new.test.sh'
reset

# --- close 4: what the self-review weighs is not a gate ----------------------------

# Removed blocks, a new pattern matcher and declined findings are the
# self-review's judgment: close 4 asks for no Dropped, Near-miss, Declined or
# Probe line, and a free-text one is not refused.
reset; put scripts/m.sh 'grep -q foo "$f"'; printf 'gone\n' > "$work/scripts/old.sh"
run4; close 4
admitted "a new matcher and a removed line, with no Near-miss or Dropped line"
run4; add 'Declined: C1: claim: the caller guards it' 'Declined: C2: out of scope' 'Probe: C9: bash x.sh => exit 2, usage printed'; close 4
admitted "a claim with no probe, an unmarked decline and a free-text probe"
reset

# --- close 4: every gap in one message, then the single fix ----------------------

reset; put tests/new.test.sh 'echo new'
run4bare; held=$(cat "$rf"); close 4
refused "all three gaps at once" 'no Reverted-fix line for tests/new.test.sh'
for frag in 'no Round line for self-review' 'no Stop line for self-review'; do
  check "the one message also names: $frag" yes "$(has "$frag" "$err")"
done
add 'Reverted-fix: tests/new.test.sh: n/a: a fixture' 'Round: self-review 1: clean' 'Stop: self-review: tree unchanged'
close 4
admitted "close 4 once every item is present"
check "the closed line carries a range" 1 "$(grep -c '^- \[x\] 4 · .*([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9])$' "$rf")"
reset

# next closes the open phase through the same gate: it is no way round it.
reset; put tests/new.test.sh 'echo new'
run4; held=$(cat "$rf"); call "$work" next 5 --file "$rf"
refused "next 5 over phase 4" 'no Reverted-fix line for tests/new.test.sh'
add 'Reverted-fix: tests/new.test.sh: n/a: a fixture'; call "$work" next 5 --file "$rf"
check_rc "next 5 over phase 4 once the line is present" 0 "$status"
reset

# The diff and the base are a failed read, never a clean verdict.
nogit=$tmp/nogit; mkdir -p "$nogit"
run4; held=$(cat "$rf"); call "$nogit" close 4 --file "$rf"
check_rc "close 4 outside a git checkout is a tooling error" 2 "$status"
check "the tooling error says why" yes "$(has 'close 4' "$err")"
check "outside a checkout the record is as it was" "$held" "$(cat "$rf")"
bare=$tmp/norigin; git init -q -b main "$bare"
git -C "$bare" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
run4; held=$(cat "$rf"); call "$bare" close 4 --file "$rf"
check_rc "close 4 where origin/HEAD does not resolve is a tooling error" 2 "$status"
check "the error names the base" yes "$(has 'origin/HEAD' "$err")"
check "an unresolved base leaves the record as it was" "$held" "$(cat "$rf")"
# The mechanic reaches no host: an origin/HEAD that is missing is read as missing,
# and the origin is never asked to refresh it.
shim=$tmp/shim; mkdir -p "$shim"
printf '#!/bin/sh\ncase "$*" in *set-head*) echo "$*" >> %s/set-head.log ;; esac\nexec %s "$@"\n' "$tmp" "$(command -v git)" > "$shim/git"
chmod +x "$shim/git"
git -C "$bare" remote add origin https://github.com/owner/repo.git
run4; PATH=$shim:$PATH call "$bare" close 4 --file "$rf"
check_rc "close 4 with an origin that has no HEAD is still tooling" 2 "$status"
check "and the origin is never asked to refresh its HEAD" "" "$(cat "$tmp/set-head.log" 2>/dev/null)"
git -C "$bare" remote remove origin

# The two reads a produced red line takes, the diff since its head and the
# untracked files among its paths, are tooling when they fail, never fresh.
reset; put tests/new.test.sh 'echo new'; put src/x.txt 'fixed'; g add -A; g commit -q -m 'test and fix'
at=$(g rev-parse HEAD)
for read in 'diff:--literal-pathspecs diff:cannot read the diff of tests/new.test.sh since' 'ls-files:--literal-pathspecs ls-files:cannot list the untracked files among tests/new.test.sh'; do
  name=${read%%:*} rest=${read#*:} match=${rest%%:*} msg=${rest#*:}
  printf '#!/bin/sh\ncase "$*" in *"%s"*) exit 2 ;; esac\nexec %s "$@"\n' "$match" "$(command -v git)" > "$shim/git"
  run4; add "Reverted-fix: tests/new.test.sh: red at $at reverting src/x.txt"; held=$(cat "$rf")
  PATH=$shim:$PATH call "$work" close 4 --file "$rf"
  check_rc "a failed $name read of a red line is tooling" 2 "$status"
  check "and says which read failed: $name" yes "$(has "$msg" "$err")"
  check "and the record is as it was: $name" "$held" "$(cat "$rf")"
done
rm "$shim/git"
reset

# A phase that is not open is refused before any evidence is read.
reset; put tests/new.test.sh 'echo new'
run4; add 'Reverted-fix: tests/new.test.sh: n/a: a fixture'; close 4; close 4
check_rc "closing phase 4 twice" 1 "$status"
check "the second close is refused as not open" 'phase 4 is not open' "$err"
reset

# --- close 4: the self-review loop -------------------------------------------------

run4bare; held=$(cat "$rf"); close 4
refused "phase 4 with no self-review round and no stop" 'no Round line for self-review: add `Round: self-review <n>: <text>`, one per self-review round'
check "the same refusal names the missing stop" yes "$(has 'no Stop line for self-review: add `Stop: self-review: <tree unchanged|cap>`' "$err")"

run4bare; add 'Round: self-review 1: 2 findings, both fixed'; held=$(cat "$rf"); close 4
refused "a round with no stop" 'no Stop line for self-review'
check "the round is not asked for" no "$(has 'no Round line' "$err")"

run4bare; add 'Stop: self-review: tree unchanged'; held=$(cat "$rf"); close 4
refused "a stop with no round" 'no Round line for self-review'

run4bare; add 'Round: self-review 0: clean' 'Stop: self-review: tree unchanged'; held=$(cat "$rf"); close 4
refused "a round numbered 0" 'no Round line for self-review'

run4bare; add 'Round: self-review 1:' 'Stop: self-review: tree unchanged'; held=$(cat "$rf"); close 4
refused "a round with no text" 'no Round line for self-review'

run4bare; add 'Round: self-review 1: clean' 'Stop: self-review: small lane'; held=$(cat "$rf"); close 4
refused "a host-loop stop reason" "Stop line for self-review has reason 'small lane', which is not one of tree unchanged, cap"

run4bare; add 'Round: self-review 1: clean' 'Stop: self-review: cap' 'Stop: self-review: whenever'; held=$(cat "$rf"); close 4
refused "the last Stop line decides" "Stop line for self-review has reason 'whenever'"

run4bare; add 'Round: self-review 1: fixed' 'Round: self-review 2:' 'Stop: self-review: cap'; held=$(cat "$rf"); close 4
refused "a malformed later round beside a good one" 'no Round line for self-review'
check "and names the shape" yes "$(has 'each in that shape' "$err")"

run4bare; add 'Round: self-review 1: clean' 'Stop: self-review: tree unchanged'; close 4
admitted "one clean round, stopped on an unchanged tree"

run4bare; add '- Round: self-review 1: 1 finding, fixed' '- Round: self-review 2: 1 finding, fixed' '- Stop: self-review: cap'; close 4
admitted "bulleted rounds stopped at the cap"

run4bare; add 'Round: copilot 1: clean' 'Stop: copilot: tree unchanged'; held=$(cat "$rf"); close 4
refused "a host reviewer's lines are not the self-review's" 'no Round line for self-review'

run4bare; add 'Round: self-reviewer 1: clean' 'Stop: self-reviewer: tree unchanged'; held=$(cat "$rf"); close 4
refused "a longer label is another reviewer's" 'no Round line for self-review'
check "and its stop is not the loop's" yes "$(has 'no Stop line for self-review' "$err")"

run4bare; add '`Round: self-review 1: clean`' '`Stop: self-review: tree unchanged`'; held=$(cat "$rf"); close 4
refused "a quoted line is an example" 'no Round line for self-review'

run4bare; add '  Round: self-review 1: clean' '  Stop: self-review: tree unchanged'; held=$(cat "$rf"); close 4
refused "an indented line is no gate line" 'no Round line for self-review'


finish
