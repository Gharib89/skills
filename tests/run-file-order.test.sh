#!/usr/bin/env bash
# Split by behaviour from tests/run-file.test.sh: record naming, phase order and next cases.
# The run-file mechanic: the Run file's checklist, its flips and its timing
# arithmetic. Every case drives the mechanic against a scratch directory under
# the OS temp dir; the mechanic reaches no host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/run-file.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

usage='usage: run-file init <issue|slug> [--scratchpad <dir>] [--rebuild] [--state <n>=<spec>] [--tripwires <t>] [--verifications <v>] [--reviewers <r>] [--legs <l>] [--from-profile [<path>]] [--criteria <file|->] | open <n> | next <n> | close <n> [--result <name>=<word>[: <note>]] [--head <sha>] | skip <n> <reason> | grade <patch|minor|breaking> | gate record <file|-> [--head <sha>] | gate read --head <sha> | gate clean <ci-file|-> --head <sha> | gate summary <pr> | timing | ran <name>... <where> | prove <test> <path>... [--fix <commit>] <where> [-- <command>...] | probe <ref> <where> -- <command>... | call <why> <where> -- <command>... | note <section> <line>, each taking <where>: --file <path> or --issue <n|slug> [--scratchpad <dir>, default ${XDG_STATE_HOME:-~/.local/state}/ship/<repo key>] resolving <root>/ship-<issue>/run.md'

out()  { bash "$m" "$@" 2>/dev/null; }
err()  { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()   { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

# `close 4` reads the checkout's diff, which here is the change under test. A
# case that needs only the flip runs it from a repo with no diff, with a copy of
# the mechanic; the gates themselves are `tests/run-file-gates.test.sh`'s.
quiet=$tmp/quiet-bin quietrepo=$tmp/quiet
mkdir -p "$quiet" "$quietrepo.origin"
cp -r skills/ship/scripts/run-file.sh skills/ship/scripts/_lib.sh skills/ship/scripts/lib "$quiet/"
git init -q --bare -b main "$quietrepo.origin"
git init -q -b main "$quietrepo"
git -C "$quietrepo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
git -C "$quietrepo" remote add origin "$quietrepo.origin"
git -C "$quietrepo" push -q origin main 2>/dev/null
git -C "$quietrepo" remote set-head origin main
qout() { ( cd "$quietrepo" && bash "$quiet/run-file.sh" "$@" 2>/dev/null ); }
qrc()  { ( cd "$quietrepo" && bash "$quiet/run-file.sh" "$@" >/dev/null 2>&1 ); echo $?; }

# `open` refuses a phase over an earlier one never flipped, so a fixture that
# opens a later phase first marks the phases below it done.
done_below2=(--state "0=done" --state "1=done")
done_below4=("${done_below2[@]}" --state "2=done" --state "3=done")
done_below5=("${done_below4[@]}" --state "4=done")

# --- naming the record by its issue ---------------------------------------------

# A run that lost the path to its own record after a context compaction called
# `close` without `--file` twice (/ship 205). The layout is the mechanic's, so
# the mechanic resolves it: the run brings the scratchpad its environment block
# names and the issue it was invoked on, and the usage line carries the rest.
i=$(out init 218 --scratchpad "$tmp" "${done_below2[@]}" --state 2=done --state 3=skipped:fixture | jq -r '.run_file')

check "--issue resolves the record under the scratchpad" \
  "$i" "$(out open 4 --issue 218 --scratchpad "$tmp" | jq -r '.run_file')"
check "the line it flipped is the one --file flips" \
  1 "$(grep -c '^- \[ \] 4 · .* in_progress ([0-9][0-9]:[0-9][0-9]→)$' "$i")"
printf '%s\n' 'Round: self-review 1: clean' 'Stop: self-review: tree unchanged' >> "$i"
check_rc "close by --issue exits ok" 0 "$(qrc close 4 --issue 218 --scratchpad "$tmp")"
check "skip by --issue carries the reason" \
  'small lane' "$(out skip 3 'small lane' --issue 218 --scratchpad "$tmp" | jq -r '.reason')"
check "timing by --issue reads the same file" \
  "$i" "$(out timing --issue 218 --scratchpad "$tmp" | jq -r '.run_file')"

# An explicit path outranks the pair that would resolve one: a run that knows
# where its record is never has the mechanic guess.
j=$(out init 219 --scratchpad "$tmp" "${done_below4[@]}" | jq -r '.run_file')
check "--file wins over --issue" \
  "$j" "$(out open 4 --file "$j" --issue 218 --scratchpad "$tmp" | jq -r '.run_file')"

# An empty value is malformed, not absent: `--file ""` from an unset variable
# used to fall through to --issue and flip a record the caller never named.
check "an empty --file is refused, not resolved by --issue" \
  '--file needs a path' "$(err open 4 --file '' --issue 219 --scratchpad "$tmp")"
check_rc "an empty --file is malformed" 2 "$(rc open 4 --file '' --issue 219 --scratchpad "$tmp")"

# Neither is the usage error it always was: the flip has no record to act on.
check "neither --file nor --issue is the usage line" "$usage" "$(err close 4)"
check_rc "neither --file nor --issue is malformed" 2 "$(rc close 4)"

# The refusal names the path it resolved, so a run that brought the wrong
# scratchpad reads which one it asked for rather than that something was missing,
# and the rebuild, for the record a subagent removed rather than overwrote.
check "an --issue with no record names the path it resolved and the rebuild" \
  "no Run file at $tmp/ship-nothing-here/run.md: check that path first; if it is the right one, a subagent removed the Run file; rebuild it with \`run-file init <issue> --rebuild [--scratchpad <dir>]\`, re-passing the --tripwires, --verifications, --reviewers, --legs and --criteria the run began with and one --state per phase the transcript accounts for (open for the one that was running, or 3 and 4 both open if they overlapped, no invented range), then log what was lost in the deviations log" \
  "$(err close 4 --issue nothing-here --scratchpad "$tmp")"

# With no --scratchpad the record root is the state directory's, so a TMPDIR no
# longer decides where a run looks: the lookup lands under XDG_STATE_HOME
# (`tests/run-file-record.test.sh` proves the round trip and the repo key) and
# names that path.
e=$(XDG_STATE_HOME=$tmp/state TMPDIR=$tmp/os err timing --issue 218)
check "--scratchpad defaults to the state directory, not the OS temp dir" yes \
  "$([[ $e == "no Run file at $tmp/state/ship/"*"/ship-218/run.md: check that path first; if it is the right one, a subagent removed the Run file; rebuild it with \`run-file init <issue> --rebuild [--scratchpad <dir>]\`"* ]] && echo yes || echo no)"

# --- phase order ---------------------------------------------------------------

# A phase opened over an earlier one that was never flipped leaves that one
# unticked and `unverified` for good (/ship 365), so `open` refuses it and names
# the lowest such phase with the recovery that works for it.
q=$(out init 600 --scratchpad "$tmp" | jq -r '.run_file')
for p in 0 1 2 3; do out open "$p" --file "$q" >/dev/null; out close "$p" --file "$q" >/dev/null; done
held=$(cat "$q")
e=$(out open 5 --file "$q"); erc=$?
check "open over an earlier phase never flipped names it and the recovery" \
  'phase 4 is neither closed nor skipped. If it ran: `run-file open 4`, `run-file close 4`, then note in the deviations log that its stamp is the recovery time, so its minutes and any start→PR or PR→gate figure it bounds reflect the recovery, plus when it really ran if the transcript holds that. If it did not run: `run-file skip 4 <reason>`. Then retry `run-file open 5`, which names the next such phase if any.' \
  "$(printf '%s' "$e" | jq -r '.error')"
check_rc "open over an earlier phase never flipped exits 1" 1 "$erc"
check "the refused open left the Run file byte-identical" "$held" "$(cat "$q")"

# Closed, skipped and rebuilt `done` all tick the row, so each admits the open.
out open 4 --file "$q" >/dev/null; printf '%s\n' 'Round: self-review 1: clean' 'Stop: self-review: tree unchanged' >> "$q"; qout close 4 --file "$q" >/dev/null
check_rc "open over a closed phase exits ok" 0 "$(rc open 5 --file "$q")"
out close 5 --file "$q" >/dev/null
check_rc "open over a skipped phase exits ok" 0 \
  "$(k=$(out init 601 --scratchpad "$tmp" "${done_below4[@]}" --state '4=skipped:small lane' | jq -r '.run_file'); rc open 5 --file "$k")"
check_rc "open over a phase rebuilt as done exits ok" 0 \
  "$(k=$(out init 602 --scratchpad "$tmp" "${done_below5[@]}" | jq -r '.run_file'); rc open 5 --file "$k")"

# Going back is still allowed: every phase below a closed one is already ticked.
check_rc "re-opening an earlier closed phase after later ones closed exits ok" 0 \
  "$(rc open 2 --file "$q")"

# A phase that is open is the refusal it always was, not the unflipped one.
check "an earlier phase still open answers with the open-phase refusal" \
  "phase 1 is open; close it before opening 5" \
  "$(k=$(out init 603 --scratchpad "$tmp" --state 0=done --state 1=open | jq -r '.run_file'); err open 5 --file "$k")"

# One phase, one line: a ticked copy below the checklist does not tick phase 4,
# and an unticked copy does not untick phase 2.
k=$(out init 604 --scratchpad "$tmp" "${done_below4[@]}" | jq -r '.run_file')
printf -- '- [x] 4 · a line copied into the plan (10:00→10:30)\n' >> "$k"
check_rc "a ticked copy below the checklist does not satisfy the check" 1 "$(rc open 5 --file "$k")"
k=$(out init 605 --scratchpad "$tmp" "${done_below5[@]}" | jq -r '.run_file')
printf -- '- [ ] 2 · a line copied into the plan\n' >> "$k"
check_rc "an unticked copy below the checklist does not trip the check" 0 "$(rc open 5 --file "$k")"


# --- init opens phase 0 ----------------------------------------------------------

# A bare init is the run starting, so phase 0 opens in the same call and the run
# spends no `open 0` on it. Any --state is the caller stating the whole run, so
# it opens nothing of its own.
ij=$(out init 700 --scratchpad "$tmp")
z=$(jq -r .run_file <<<"$ij")
check "a bare init opens phase 0 at the clock" \
  1 "$(grep -c '^- \[ \] 0 · .* in_progress ([0-9][0-9]:[0-9][0-9]→)$' "$z")"
check "init says which phase it opened" "0 in_progress" "$(jq -r '[.opened, .mirror] | join(" ")' <<<"$ij")"
check "init still holds exactly one open phase" 1 "$(grep -c 'in_progress ([0-9][0-9]:[0-9][0-9]→)$' "$z")"
check "init with a --state opens nothing of its own" \
  "false" "$(out init 701 --scratchpad "$tmp" --state 0=done | jq 'has("opened") or has("mirror")')"
check "init with a --state leaves phase 0 as stated" \
  "1 0" "$(grep '^- \[.\] 0 · ' "$tmp/ship-701/run.md" | grep -c '^- \[x\] ') $(grep -c 'in_progress' "$tmp/ship-701/run.md")"

# --- next ------------------------------------------------------------------------

nj=$(out next 1 --file "$z"); nrc=$?
check_rc "next exits ok" 0 "$nrc"
check "next closes the open phase and says what to mirror" \
  "0 completed" "$(jq -r '[.closed.phase, .closed.mirror] | join(" ")' <<<"$nj")"
check "next opens the target and says what to mirror" \
  "1 in_progress" "$(jq -r '[.opened.phase, .opened.mirror] | join(" ")' <<<"$nj")"
check "next reports the run file" "$z" "$(jq -r .run_file <<<"$nj")"
check "the closed line is the one close writes" \
  "$(grep '^- \[.\] 0 · ' "$z")" "$(jq -r .closed.line <<<"$nj")"
check "the opened line is the one open writes" \
  "$(grep '^- \[.\] 1 · ' "$z")" "$(jq -r .opened.line <<<"$nj")"
check "phase 0 is closed with a full range" \
  1 "$(grep -c '^- \[x\] 0 · .*([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9])$' "$z")"
check "phase 1 is open" 1 "$(grep -c '^- \[ \] 1 · .* in_progress ([0-9][0-9]:[0-9][0-9]→)$' "$z")"

held=$(cat "$z")
check "next onto the phase already open is refused" "phase 1 is already open" "$(err next 1 --file "$z")"
check "next over an earlier phase never flipped names it, as open does" \
  "phase 2 is neither closed nor skipped." "$(err next 4 --file "$z" | cut -c1-38)"
check "next over a gap names the gap with the next recovery" \
  'phase 2 is neither closed nor skipped. If it ran: `run-file next 2`, `run-file close 2`, then note in the deviations log that its stamp is the recovery time, so its minutes and any start→PR or PR→gate figure it bounds reflect the recovery, plus when it really ran if the transcript holds that. If it did not run: `run-file skip 2 <reason>`. Then retry `run-file open 4`, which names the next such phase if any. Also passed over: 3.' \
  "$(err next 4 --file "$z")"
check_rc "a refused next exits 1" 1 "$(rc next 4 --file "$z")"
check "a refused next wrote nothing, not even the close" "$held" "$(cat "$z")"
check_rc "next needs a phase number" 2 "$(rc next --file "$z")"
check_rc "next with a flag as the phase is malformed" 2 "$(rc next --x --file "$z")"

# With nothing open `next` has nothing to close, so it is `open` under the same
# order check (ship-850 closed 7, then `next 8` was refused).
out close 1 --file "$z" >/dev/null
nj=$(out next 2 --file "$z"); nrc=$?
check_rc "next with nothing open exits ok" 0 "$nrc"
check "next with nothing open closes nothing" "null" "$(jq -c .closed <<<"$nj")"
check "next with nothing open opens the target, as open does" \
  "2 in_progress $(grep '^- \[.\] 2 · ' "$z")" \
  "$(jq -r '[.opened.phase, .opened.mirror, .opened.line] | join(" ")' <<<"$nj")"
out close 2 --file "$z" >/dev/null
held=$(cat "$z")
check "next with nothing open still refuses a gap" \
  "phase 3 is neither closed nor skipped." "$(err next 5 --file "$z" | cut -c1-38)"
check "a refused next with nothing open wrote nothing" "$held" "$(cat "$z")"

# Every passed-over phase is named, not only the lowest (ship-849 passed over 5).
g=$(out init 606 --scratchpad "$tmp" "${done_below2[@]}" | jq -r '.run_file')
check "open over several never-flipped phases names the others" \
  'Then retry `run-file open 5`, which names the next such phase if any. Also passed over: 3, 4.' \
  "$(err open 5 --file "$g" | grep -o 'Then retry.*')"

# Two open (the 3/4 overlap): next cannot say which to close, so it names one.
y=$(out init 702 --scratchpad "$tmp" "${done_below2[@]}" --state 2=done | jq -r .run_file)
out open 3 --file "$y" >/dev/null; out open 4 --file "$y" >/dev/null
held=$(cat "$y")
check "next with two phases open names the one to close first" \
  'phases 3 and 4 are both open; close 3 first with `run-file close 3`, then retry `run-file next 5`' \
  "$(err next 5 --file "$y")"
check_rc "next with two phases open exits 1" 1 "$(rc next 5 --file "$y")"
check "it wrote nothing" "$held" "$(cat "$y")"

# --- close on a phase that was never opened ------------------------------------

p=$(out init 703 --scratchpad "$tmp" | jq -r .run_file)
check "close on a pending phase names open as the way forward" \
  'phase 3 was never opened; run `run-file open 3` first, then close it' "$(err close 3 --file "$p")"
check_rc "close on a pending phase exits 1" 1 "$(rc close 3 --file "$p")"
out skip 3 'small lane' --file "$p" >/dev/null
check "close on a skipped phase is the not-open refusal" "phase 3 is not open" "$(err close 3 --file "$p")"

# --- the 3/4 overlap -----------------------------------------------------------

# Phase 4 begins while the phase 3 verifications run, so open 4 admits one open
# phase and no more; every other open-while-open is the refusal it always was.
y=$(out init 704 --scratchpad "$tmp" "${done_below2[@]}" --state 2=done | jq -r .run_file)
out open 3 --file "$y" >/dev/null
check_rc "open 4 while 3 is open exits ok" 0 "$(rc open 4 --file "$y")"
check "both phases carry an open stamp" \
  2 "$(grep -c '^- \[ \] [34] · .* in_progress ([0-9][0-9]:[0-9][0-9]→)$' "$y")"
check "a fifth open while both are open names the first" \
  "phase 3 is open; close it before opening 5" "$(err open 5 --file "$y")"
check "open 3 while 4 is open stays refused" "phase 3 is already open" "$(err open 3 --file "$y")"
out close 3 --file "$y" >/dev/null
check "open 3 with only 4 open is the open-phase refusal" \
  "phase 4 is open; close it before opening 3" "$(err open 3 --file "$y")"
y=$(out init 705 --scratchpad "$tmp" "${done_below2[@]}" --state 2=done --state 3=done | jq -r .run_file)
out open 4 --file "$y" >/dev/null
check "open 5 while 4 is open stays refused" \
  "phase 4 is open; close it before opening 5" "$(err open 5 --file "$y")"
y=$(out init 706 --scratchpad "$tmp" --state 0=done --state 1=done --state 2=open | jq -r .run_file)
check "open 4 while 2 is open stays refused" \
  "phase 2 is open; close it before opening 4" "$(err open 4 --file "$y")"

# --- skip keeps the gate's order (#933) -----------------------------------------

# `open` and `close` already hold rows 5 to 8 behind phase 3; `skip` was the way
# round that, so a phase 3 still running could be stepped over.
y=$(out init 707 --scratchpad "$tmp" "${done_below2[@]}" --state 2=done --state 3=open | jq -r .run_file)
held=$(cat "$y")
for n in 5 6 7 8; do
  check "skip $n while phase 3 is open names phase 3" \
    "phase 3 is open; close it before skipping $n: an open phase 3 settles with \`close 3 --result <name>=n/a\` per pending Verification" "$(err skip "$n" 'small lane' --file "$y")"
  check_rc "skip $n while phase 3 is open exits 1" 1 "$(rc skip "$n" 'small lane' --file "$y")"
done
check "the refused skips wrote nothing" "$held" "$(cat "$y")"
out open 4 --file "$y" >/dev/null
check "skip 5 while 3 and 4 are open still names phase 3" \
  "phase 3 is open; close it before skipping 5: an open phase 3 settles with \`close 3 --result <name>=n/a\` per pending Verification" "$(err skip 5 'small lane' --file "$y")"
# A skip over an open phase 3 itself names the route out: close 3 with an n/a
# result per pending Verification (#989).
y=$(out init 709 --scratchpad "$tmp" "${done_below2[@]}" --state 2=done | jq -r .run_file)
out next 3 --file "$y" >/dev/null
check "skip 3 after next 3 names close 3 --result" \
  "phase 3 is open; close it before skipping it: an open phase 3 settles with \`close 3 --result <name>=n/a\` per pending Verification" "$(err skip 3 'small lane' --file "$y")"
check_rc "skip 3 after next 3 still exits 1" 1 "$(rc skip 3 'small lane' --file "$y")"
y=$(out init 708 --scratchpad "$tmp" "${done_below2[@]}" --state 2=done --state 3=done --state 4=done | jq -r .run_file)
check_rc "skip 5 once phase 3 is closed is admitted" 0 "$(rc skip 5 'small lane' --file "$y")"

finish
