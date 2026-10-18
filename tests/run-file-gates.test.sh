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

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

bin=$tmp/bin work=$tmp/work origin=$tmp/origin.git
mkdir -p "$bin"
cp -r skills/ship/scripts/run-file.sh skills/ship/scripts/_lib.sh skills/ship/scripts/lib "$bin/"
cat > "$bin/dropped-lines.sh" <<'STUB'
#!/usr/bin/env bash
printf '{"base":"x","blocks":[{"id":"scripts/old.sh:1","file":"scripts/old.sh","line":1,"lines":3,"text":"t"}]}\n'
STUB

git init -q --bare -b main "$origin"
git init -q -b main "$work"
g() { git -C "$work" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
put() { mkdir -p "$(dirname "$work/$1")"; printf '%s\n' "$2" > "$work/$1"; }
put tests/old.test.sh 'echo old'
put scripts/old.sh 'grep -q a b'
put src/x.txt 'x'
put keep.txt 'k'
g add -A && g commit -q -m base
g remote add origin "$origin"
g push -q origin main 2>/dev/null
g remote set-head origin main
base=$(g rev-parse HEAD)
g checkout -q -b feat/x-488
reset() { g reset -q --hard "$base"; g clean -fdq; }

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
