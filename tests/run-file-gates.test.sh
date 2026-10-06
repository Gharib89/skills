#!/usr/bin/env bash
# The run-file mechanic's self-review gates: `close 4` refuses until the Run file
# carries the evidence the diff calls for, `close 7` until each reviewer has a
# stop reason and a round, and `grade` writes the run's grade. Driven over a
# fixture repo with an origin, so the diff is the real `git diff` against the
# real merge base; `dropped-lines` is a stub beside a copy of the mechanic, so
# each case names the blocks it wants and the suite stands on this mechanic alone.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

bin=$tmp/bin work=$tmp/work origin=$tmp/origin.git
mkdir -p "$bin"
cp skills/ship/scripts/run-file.sh skills/ship/scripts/_lib.sh "$bin/"
cat > "$bin/dropped-lines.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$DL_ARGS"
if [ -n "${DL_JSON+x}" ]; then printf '%s\n' "$DL_JSON"; else printf '{"base":"x","blocks":[]}\n'; fi
exit "${DL_RC:-0}"
STUB
export DL_ARGS=$tmp/dl.args
blocks() { DL_JSON=$(jq -nc '{base: "x", blocks: [$ARGS.positional[] | {id: ., file: "f", line: 1, lines: 3, text: "t"}]}' --args "$@"); export DL_JSON; }
noblocks() { unset DL_JSON DL_RC; }

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
reset() { g reset -q --hard "$base"; g clean -fdq; noblocks; }

# One Run file per case, so a refusal's "changes nothing" is that file's bytes.
n=100
rf=""
run4() { n=$((n + 1)); rf=$(bash "$bin/run-file.sh" init "$n" --scratchpad "$tmp/sp" \
  --state 0=done --state 1=done --state 2=done --state 3=done --state 4=open | jq -r .run_file); }
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

reset; put tests/new.test.sh 'echo new'
run4; held=$(cat "$rf"); close 4
refused "an added test file with no Reverted-fix line" 'no Reverted-fix line for tests/new.test.sh: add `Reverted-fix: tests/new.test.sh: red` or `Reverted-fix: tests/new.test.sh: n/a: <reason>`'
check "close 4 names the phase it refused" 'phase 4 cannot close: no Reverted-fix line for tests/new.test.sh: add `Reverted-fix: tests/new.test.sh: red` or `Reverted-fix: tests/new.test.sh: n/a: <reason>`' "$err"

add 'Reverted-fix: tests/new.test.sh: red'; close 4
admitted "a red line for the added test file"

run4; add '- Reverted-fix: tests/new.test.sh: n/a: pure docs fixture'; close 4
admitted "a bulleted n/a line with a reason"

# A validator gets a negative control: each of these must be refused.
run4; add 'Reverted-fix: tests/new.test.sh: n/a:'; held=$(cat "$rf"); close 4
refused "an n/a line with no reason" 'no Reverted-fix line for tests/new.test.sh'
run4; add 'Reverted-fix: tests/new.test.sh: n/a:   '; held=$(cat "$rf"); close 4
refused "an n/a line with a blank reason" 'no Reverted-fix line for tests/new.test.sh'
run4; add 'Reverted-fix: tests/new.test.sh: maybe'; held=$(cat "$rf"); close 4
refused "a Reverted-fix word outside red and n/a" 'no Reverted-fix line for tests/new.test.sh'
run4; add 'Reverted-fix: tests/other.test.sh: red'; held=$(cat "$rf"); close 4
refused "a Reverted-fix line for another test file" 'no Reverted-fix line for tests/new.test.sh'
run4; add '  Reverted-fix: tests/new.test.sh: red'; held=$(cat "$rf"); close 4
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

# --- close 4: dropped-lines ------------------------------------------------------

blocks 'src/a.sh:12' 'old.sh:3'
run4; held=$(cat "$rf"); close 4
refused "dropped blocks with no disposition" 'no disposition for removed block src/a.sh:12: add `Dropped: src/a.sh:12 re-homed at <path>` or `Dropped: src/a.sh:12 dropped on purpose: <why>`'
check "every undisposed block is named in the one message" yes "$(has 'no disposition for removed block old.sh:3' "$err")"
check "the read was taken from the diff's merge base" "--base $base" "$(cat "$DL_ARGS")"

run4; add 'Dropped: src/a.sh:12 re-homed at src/b.sh' 'Dropped: old.sh:3 dropped on purpose: obsolete flag'; close 4
admitted "a re-homed line and a dropped-on-purpose line"

run4; add 'Dropped: src/a.sh:12 re-homed at src/b.sh'; held=$(cat "$rf"); close 4
refused "one block left undisposed" 'no disposition for removed block old.sh:3'
check "the disposed block is not named" no "$(has 'removed block src/a.sh:12' "$err")"

run4; add 'Dropped: src/a.sh:12 re-homed at ' 'Dropped: old.sh:3 dropped on purpose:'; held=$(cat "$rf"); close 4
refused "dispositions with no path and no reason" 'no disposition for removed block src/a.sh:12'
check "a dropped-on-purpose with no why is refused too" yes "$(has 'no disposition for removed block old.sh:3' "$err")"

blocks 'src/a.sh:12'
run4; add 'Dropped: src/a.sh:1 re-homed at src/b.sh'; held=$(cat "$rf"); close 4
refused "a disposition for a block whose id is a prefix of this one" 'no disposition for removed block src/a.sh:12'

blocks 'my file.sh:7'
run4; add 'Dropped: my file.sh:7 dropped on purpose: moved by hand'; close 4
admitted "an id holding a space, matched by exact prefix"

# The read failing is a tooling answer, never a clean diff.
blocks 'src/a.sh:12'; export DL_RC=3
run4; held=$(cat "$rf"); close 4
check_rc "dropped-lines exiting non-zero is a tooling error" 2 "$status"
check "the tooling error names dropped-lines" yes "$(has 'dropped-lines' "$err")"
check "a tooling error leaves the record as it was" "$held" "$(cat "$rf")"
noblocks; export DL_JSON='not json'
run4; held=$(cat "$rf"); close 4
check_rc "dropped-lines printing non-JSON is a tooling error" 2 "$status"
check "the non-JSON error names dropped-lines" yes "$(has 'dropped-lines' "$err")"
check "the non-JSON error leaves the record as it was" "$held" "$(cat "$rf")"
export DL_JSON='{"base":"x"}'
run4; close 4
check_rc "dropped-lines printing no blocks list is a tooling error" 2 "$status"
noblocks

# --- close 4: near-miss tables ---------------------------------------------------

kinds='partial-token, quoted, indented, unbalanced, unreadable'
reset; put scripts/m.sh 'grep -q foo "$f"'
run4; held=$(cat "$rf"); close 4
refused "a new grep with no near-miss table" "scripts/m.sh has a new pattern matcher and no near-miss line for: $kinds"
check "the refusal says how to answer each kind" yes "$(has 'add one line per kind, `Near-miss: scripts/m.sh: <kind>: <test path>` or `Near-miss: scripts/m.sh: <kind>: n/a: <reason>`, or `Near-miss: scripts/m.sh: n/a: <reason>` for the whole script' "$err")"

put tests/m.test.sh 'echo t'
run4
add 'Near-miss: scripts/m.sh: partial-token: tests/m.test.sh' 'Near-miss: scripts/m.sh: quoted: tests/m.test.sh' \
    'Near-miss: scripts/m.sh: indented: tests/m.test.sh' 'Near-miss: scripts/m.sh: unbalanced: tests/m.test.sh' \
    'Near-miss: scripts/m.sh: unreadable: tests/m.test.sh' 'Reverted-fix: tests/m.test.sh: red'
close 4
admitted "five kinds each naming a test that exists"

run4
add 'Near-miss: scripts/m.sh: partial-token: tests/m.test.sh' 'Near-miss: scripts/m.sh: quoted: n/a: no comments are parsed' \
    '- Near-miss: scripts/m.sh: indented: tests/m.test.sh' 'Near-miss: scripts/m.sh: unreadable: tests/m.test.sh' 'Reverted-fix: tests/m.test.sh: red'
held=$(cat "$rf"); close 4
refused "a table missing the unbalanced kind" 'scripts/m.sh has a new pattern matcher and no near-miss line for: unbalanced:'
check "the kinds it has are not named as missing" no "$(has 'for: partial-token' "$err")"

run4
add 'Near-miss: scripts/m.sh: partial-token: tests/nope.test.sh' 'Near-miss: scripts/m.sh: quoted: n/a:' \
    'Near-miss: scripts/m.sh: indented: tests/m.test.sh' 'Near-miss: scripts/m.sh: unbalanced: tests/m.test.sh' \
    'Near-miss: scripts/m.sh: unreadable: tests/m.test.sh' 'Reverted-fix: tests/m.test.sh: red'
held=$(cat "$rf"); close 4
refused "a row naming a test that is not a file, and an n/a with no reason" "no near-miss line for: partial-token, quoted:"

# A test path that is an existing file but leaves the checkout, or climbs through
# `..`, is no test of this change: it is treated as missing.
for bad in "$work/tests/m.test.sh" "../$(basename "$work")/tests/m.test.sh" "tests/../tests/m.test.sh"; do
  run4
  add "Near-miss: scripts/m.sh: partial-token: $bad" 'Near-miss: scripts/m.sh: quoted: tests/m.test.sh' \
      'Near-miss: scripts/m.sh: indented: tests/m.test.sh' 'Near-miss: scripts/m.sh: unbalanced: tests/m.test.sh' \
      'Near-miss: scripts/m.sh: unreadable: tests/m.test.sh' 'Reverted-fix: tests/m.test.sh: red'
  held=$(cat "$rf"); close 4
  refused "a near-miss test path of $bad" 'no near-miss line for: partial-token:'
  check "the one bad kind is the only one named for $bad" no "$(has 'quoted' "${err#*no near-miss line for: }")"
done

run4
add 'Near-miss: scripts/m.sh: n/a: only a fixed string is searched, no pattern grammar' 'Reverted-fix: tests/m.test.sh: red'
close 4
admitted "one n/a line for the whole script"
run4
add 'Near-miss: scripts/m.sh: n/a:' 'Reverted-fix: tests/m.test.sh: red'; held=$(cat "$rf"); close 4
refused "a whole-script n/a with no reason" 'scripts/m.sh has a new pattern matcher'
run4
add 'Near-miss: scripts/other.sh: n/a: elsewhere' 'Reverted-fix: tests/m.test.sh: red'; held=$(cat "$rf"); close 4
refused "an n/a line for another script" 'scripts/m.sh has a new pattern matcher'

# What counts as a pattern matcher, and as new.
for body in 'if [[ $x =~ ^a ]]; then :; fi' 'egrep "a|b" f' 'echo x | sed "s/a/b/"' "awk '/^x/ { print }' f" "sed -n '/^x/p' f"; do
  reset; put scripts/m.sh "$body"
  run4; held=$(cat "$rf"); close 4
  refused "the matcher $body" 'scripts/m.sh has a new pattern matcher'
done

for body in 'echo hello' '# grep -q a b, in a comment' 'case $x in a*) ;; esac' 'cat "$f"'; do
  reset; put scripts/m.sh "$body"
  run4; close 4
  admitted "no matcher in: $body"
done

reset; put scripts/old.sh $'grep -q a b\necho added'
run4; close 4
admitted "a matcher already in the file, with no matcher among the added lines"

reset; put scripts/old.sh $'grep -q a b\ngrep -q c d'
run4; held=$(cat "$rf"); close 4
refused "a matcher among the added lines of a changed script" 'scripts/old.sh has a new pattern matcher'

reset; put tests/new.test.sh 'grep -q a b'; put docs/x.md 'grep -q a b'
run4; add 'Reverted-fix: tests/new.test.sh: red'; close 4
admitted "a grep in a test script or a non-script needs no near-miss table"

reset; put .claude/skills/x/scripts/m.sh 'grep -q foo "$f"'
run4; close 4
admitted "a matcher in the installed copy under .claude/skills needs no table: its source carries it"

reset; put scripts/m.sh 'grep -q foo "$f"'; g add scripts/m.sh; g commit -q -m 'add m'
run4; held=$(cat "$rf"); close 4
refused "a matcher committed on the branch" 'scripts/m.sh has a new pattern matcher'
reset

# --- close 4: declined findings and their probes ---------------------------------

reset
run4; add 'Declined: copilot r1 t2: the guard is already handled in the caller'; held=$(cat "$rf"); close 4
refused "a decline claiming behaviour with no probe" 'Declined: copilot r1 t2 claims behaviour and has no probe: add `Probe: copilot r1 t2: <command> => <output>`'

run4; add 'Declined: C1: already handled upstream' 'Probe: C1: bash x.sh </dev/null => exit 2, usage printed'; close 4
admitted "a behaviour decline with a probe of the same ref"

run4; add 'Declined: C1: already handled upstream' 'Probe: C2: bash x.sh => exit 2'; held=$(cat "$rf"); close 4
refused "a probe for another ref" 'Declined: C1 claims behaviour and has no probe'
run4; add 'Declined: C1: already handled upstream' 'Probe: C1: bash x.sh =>'; held=$(cat "$rf"); close 4
refused "a probe with no output" 'Declined: C1 claims behaviour and has no probe'
run4; add 'Declined: C1: already handled upstream' 'Probe: C1:  => exit 2'; held=$(cat "$rf"); close 4
refused "a probe with no command" 'Declined: C1 claims behaviour and has no probe'
run4; add 'Declined: C1: already handled upstream' 'Probe: C1: bash x.sh'; held=$(cat "$rf"); close 4
refused "a probe with no arrow" 'Declined: C1 claims behaviour and has no probe'

for phrase in 'already handled' 'ALREADY COVERED' 'Already guarded' "can't happen" 'cannot happen' 'can not happen' 'never happens' 'closes at merge' 'handled in any case'; do
  run4; add "Declined: R9: this $phrase here"; held=$(cat "$rf"); close 4
  refused "the claim '$phrase'" 'Declined: R9 claims behaviour and has no probe'
done

run4; add 'Declined: C1: a style preference, not the repo house style' 'Declined: C2: out of scope for this ticket'; close 4
admitted "a decline that claims no behaviour needs no probe"

run4; add 'Declined: C1: already handled' 'Declined: C2: cannot happen' 'Probe: C2: x => y'; held=$(cat "$rf"); close 4
refused "two declines, one probed" 'Declined: C1 claims behaviour'
check "the probed ref is not named" no "$(has 'Declined: C2' "$err")"

# --- close 4: every gap in one message, then the single fix ----------------------

reset; put tests/new.test.sh 'echo new'; put scripts/m.sh 'grep -q foo "$f"'; blocks 'src/a.sh:12'
run4; add 'Declined: C1: cannot happen'; held=$(cat "$rf"); close 4
refused "all four gaps at once" 'no Reverted-fix line for tests/new.test.sh'
for frag in 'no disposition for removed block src/a.sh:12' 'scripts/m.sh has a new pattern matcher' 'Declined: C1 claims behaviour'; do
  check "the one message also names: $frag" yes "$(has "$frag" "$err")"
done
add 'Reverted-fix: tests/new.test.sh: red' 'Dropped: src/a.sh:12 dropped on purpose: replaced' \
    'Near-miss: scripts/m.sh: n/a: fixed-string search' 'Probe: C1: bash c.sh => exit 0'
close 4
admitted "close 4 once every item is present"
check "the closed line carries a range" 1 "$(grep -c '^- \[x\] 4 · .*([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9])$' "$rf")"
reset

# next closes the open phase through the same gate: it is no way round it.
reset; put tests/new.test.sh 'echo new'
run4; held=$(cat "$rf"); call "$work" next 5 --file "$rf"
refused "next 5 over phase 4" 'no Reverted-fix line for tests/new.test.sh'
add 'Reverted-fix: tests/new.test.sh: red'; call "$work" next 5 --file "$rf"
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

# A phase that is not open is refused before any evidence is read.
reset; put tests/new.test.sh 'echo new'
run4; add 'Reverted-fix: tests/new.test.sh: red'; close 4; close 4
check_rc "closing phase 4 twice" 1 "$status"
check "the second close is refused as not open" 'phase 4 is not open' "$err"
reset

# --- close 7 ---------------------------------------------------------------------

stops='cap, tree unchanged, small lane, auto-once, not reviewed'
run7; held=$(cat "$rf"); close 7
refused "phase 7 with no stop and no round" 'no Stop line for copilot: add `Stop: copilot: <cap|tree unchanged|small lane|auto-once|not reviewed>`'
check "the same refusal names the other reviewer's stop" yes "$(has 'no Stop line for claude' "$err")"
check "and each reviewer's missing round" yes "$(has 'no Round line for copilot: add `Round: copilot <n>: <text>`, one per round, unless it stopped `not reviewed`' "$err")"
check "and the other's" yes "$(has 'no Round line for claude' "$err")"

run7; add 'Stop: copilot: cap' 'Stop: claude: auto-once' 'Round: copilot 1: 2 findings, both fixed' 'Round: copilot 2: clean' 'Round: claude 1: clean'
close 7
admitted "a stop and a round for each reviewer"

run7; add 'Stop: copilot: not reviewed' 'Stop: claude: small lane' 'Round: claude 1: clean'
close 7
admitted "a not-reviewed reviewer needs no round"

run7; add '- Stop: copilot: tree unchanged' '- Round: copilot 1: clean' 'Stop: claude: not reviewed'
close 7
admitted "bulleted stop and round lines"

run7; add 'Stop: copilot: cap' 'Stop: claude: not reviewed' 'Round: copilot 1: clean'; close 7
admitted "one reviewer with rounds and one not reviewed"

# `not reviewed` has two meanings: a fallback that was never invoked (no round) and
# a round that landed whose threads could not be read (a round, then the stop).
run7; add 'Round: copilot 1: 2 findings, both fixed' 'Stop: copilot: auto-once' 'Stop: claude: not reviewed'; close 7
admitted "a fallback never invoked: its Stop line alone, the primary's round and auto-once"
run7; add 'Round: copilot 1: clean' 'Stop: copilot: cap' 'Round: claude 1: landed, threads unreadable' 'Stop: claude: not reviewed'; close 7
admitted "a Round line beside Stop: not reviewed, a round that landed with unreadable threads"

run7; add 'Stop: copilot: cap' 'Stop: claude: not reviewed'; held=$(cat "$rf"); close 7
refused "a stopped reviewer with no round" 'no Round line for copilot'
check "the not-reviewed reviewer is not asked for a round" no "$(has 'no Round line for claude' "$err")"
check "no Stop is asked for" no "$(has 'no Stop line' "$err")"

run7; add 'Stop: copilot: cap' 'Stop: claude: whenever' 'Round: copilot 1: x' 'Round: claude 1: x'; held=$(cat "$rf"); close 7
refused "a stop reason outside the list" "Stop line for claude has reason 'whenever', which is not one of $stops"
check "the valid one is left alone" no "$(has 'copilot' "$err")"

run7; add 'Stop: copilot: not reviewed: blocked' 'Stop: claude: cap' 'Round: claude 1: x'; held=$(cat "$rf"); close 7
refused "a reason that only starts with a listed one" "Stop line for copilot has reason 'not reviewed: blocked'"

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
