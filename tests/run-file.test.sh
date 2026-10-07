#!/usr/bin/env bash
# The run-file mechanic: the Run file's checklist, its flips and its timing
# arithmetic. Every case drives the mechanic against a scratch directory under
# the OS temp dir; the mechanic reaches no host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/run-file.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

usage='usage: run-file init <issue|slug> [--scratchpad <dir>] [--rebuild] [--state <n>=<spec>] [--tripwires <t>] [--verifications <v>] [--reviewers <r>] [--legs <l>] [--from-profile [<path>]] | open <n> | next <n> | close <n> [--result <name>=<word>[: <note>]] | skip <n> <reason> | grade <patch|minor|breaking> | gate record <file|-> [--head <sha>] | gate read --head <sha> | gate clean <ci-file|-> --head <sha> | timing | prove <test> <path>... | probe <ref> <where> -- <command>..., each taking <where>: --file <path> or --issue <n|slug> [--scratchpad <dir>, default <git common dir>/ship] resolving <root>/ship-<issue>/run.md'

out()  { bash "$m" "$@" 2>/dev/null; }
err()  { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()   { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

# `close 4` reads the checkout's diff, which here is the change under test. A
# case that needs only the flip runs it from a repo with no diff, beside a copy
# of the mechanic whose `dropped-lines` finds nothing; the gates themselves are
# `tests/run-file-gates.test.sh`'s.
quiet=$tmp/quiet-bin quietrepo=$tmp/quiet
mkdir -p "$quiet" "$quietrepo.origin"
cp skills/ship/scripts/run-file.sh skills/ship/scripts/_lib.sh "$quiet/"
printf '#!/usr/bin/env bash\nprintf '"'"'{"base":"x","blocks":[]}\\n'"'"'\n' > "$quiet/dropped-lines.sh"
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

# --- init ----------------------------------------------------------------------

f=$(out init 192 --scratchpad "$tmp" \
      --tripwires 'None' \
      --verifications 'github-mechanics' \
      --reviewers 'copilot (on-request), claude (on-request)' \
      --legs 'None' | jq -r '.run_file')

check "init writes the Run file under a directory of its own" \
  "$tmp/ship-192/run.md" "$f"

check "init writes exactly ten checklist lines" \
  10 "$(grep -c '^- \[ \] ' "$f")"

check "the fixed wording, with the profile tails substituted" \
  '- [ ] 0 · Isolate: preflight, read the issue, worktree (or in place) on a fresh branch off the default
- [ ] 1 · Understand: derive success, claim, apply spec precedence
- [ ] 2 · Implement: classify (docs/code/infra), lane keys, TDD per class, tripwires None
- [ ] 3 · Verify: github-mechanics scoped to what changed
- [ ] 4 · Docs-sync + self-review: sync docs first, then `code-review` on the diff, auto-triage
- [ ] 5 · Local gate: base-fresh, then the repo'"'"'s gate, all green
- [ ] 6 · Open PR: non-draft, Conventional-Commit title, Closes, reflect on the issue
- [ ] 7 · Reviewers: copilot (on-request), claude (on-request), one bounded pass each
- [ ] 8 · CI: resolve any conflict, land None green
- [ ] 9 · Merge gate: summary, default human approval or clean opt-in (unattended: summary as PR comment, return)' \
  "$(grep '^- \[ \] ' "$f" | sed 's/ in_progress ([0-9][0-9]:[0-9][0-9]→)$//')"

# The informational reads a run made with no mechanic behind them, one line
# each, so the ones that recur across runs can be promoted to a mechanic.
check "init gives direct reads a section of their own, after the deviations log" \
  '## Deviations log

(none yet)

## Direct reads

(none yet)' \
  "$(sed -n '/^## Deviations log$/,$p' "$f")"

check "init returns the ten items for the mirror" \
  10 "$(out init 193 --scratchpad "$tmp" | jq '.items | length')"

check "a slug argument names the directory" \
  "$tmp/ship-body-rewrite/run.md" \
  "$(out init body-rewrite --scratchpad "$tmp" | jq -r '.run_file')"

check_rc "init refuses to overwrite an existing Run file" 1 "$(rc init 192 --scratchpad "$tmp")"

# --- open and close ------------------------------------------------------------

g=$(out init 200 --scratchpad "$tmp" "${done_below2[@]}" --state 2=done --state 3=skipped:fixture --state 4=done | jq -r '.run_file')
line() { grep "^- \[.\] $1 · " "$g"; }

o=$(out open 5 --file "$g"); orc=$?
check_rc "open exits ok" 0 "$orc"
check "the open line carries one half-range" \
  1 "$(line 5 | grep -c 'in_progress ([0-9][0-9]:[0-9][0-9]→)$')"
check "an open phase stays unchecked" 1 "$(line 5 | grep -c '^- \[ \] ')"
check "open tells the mirror what to set" in_progress "$(printf '%s' "$o" | jq -r '.mirror')"

c=$(out close 5 --file "$g"); crc=$?
check_rc "close exits ok" 0 "$crc"
check "close leaves one full range and no in_progress" \
  1 "$(line 5 | grep -c '^- \[x\] .*([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9])$')"
check "close tells the mirror what to set" completed "$(printf '%s' "$c" | jq -r '.mirror')"

# --- refusals ------------------------------------------------------------------

out open 2 --file "$g" >/dev/null
before=$(cat "$g")
check "a second open is refused" "phase 2 is open; close it before opening 3" "$(err open 3 --file "$g")"
check_rc "a second open exits 1" 1 "$(rc open 3 --file "$g")"
check "a refused open changes nothing" "$before" "$(cat "$g")"

check "close on a phase never opened is refused, naming open" \
  'phase 7 was never opened; run `run-file open 7` first, then close it' "$(err close 7 --file "$g")"
check_rc "close on a phase that is not open exits 1" 1 "$(rc close 7 --file "$g")"

out close 2 --file "$g" >/dev/null
check "close on an already closed phase is refused" \
  "phase 2 is not open" "$(err close 2 --file "$g")"

grep -v '^- \[.\] 8 · ' "$g" > "$tmp/gapped.md"
check "a flip whose line is absent names the line and the rebuild" \
  "no phase 8 line in $tmp/gapped.md: a subagent overwrote the Run file; rebuild it with \`run-file init <issue> --rebuild [--scratchpad <dir>]\`, re-passing the --tripwires, --verifications, --reviewers and --legs the run began with and one --state per phase the transcript accounts for (open for the one that was running, or 3 and 4 both open if they overlapped, no invented range), then log what was lost in the deviations log" \
  "$(err open 8 --file "$tmp/gapped.md")"
# A phase outside the ten is a mistyped number, not a damaged file: advice to
# rebuild would wipe an intact record.
check "a flip naming no phase of the ten is refused without the rebuild" \
  "no phase 12 line in $g" "$(err open 12 --file "$g")"
check_rc "a flip whose line is absent exits 1" 1 "$(rc open 8 --file "$tmp/gapped.md")"

check_rc "a flip on a file that is not there exits 1" 1 "$(rc open 8 --file "$tmp/nope.md")"

# --- re-open and midnight ------------------------------------------------------

out open 2 --file "$g" >/dev/null
check "re-opening appends a second half-range after the first" \
  1 "$(line 2 | grep -c '([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9]) in_progress ([0-9][0-9]:[0-9][0-9]→)$')"
out close 2 --file "$g" >/dev/null
check "closing again leaves two ranges" \
  1 "$(line 2 | grep -c '^- \[x\] .*([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9]) ([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9])$')"

# A phase opened at 23:58 and closed after midnight: the close is stamped +1d
# rather than reading as a range that runs backwards. The clock the mechanic
# reads is stubbed on PATH, so the case proves the same thing at every hour of
# the day rather than only while the real clock sits before the open stamp.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/date" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2" = "-u +%H:%M" ] && { echo 00:02; exit 0; }
exec /usr/bin/env -i PATH=/usr/bin:/bin date "$@"
STUB
chmod +x "$tmp/bin/date"
sed 's|^- \[.\] 1 · \(.*\)|- [ ] 1 · \1 in_progress (23:58→)|' "$g" > "$tmp/midnight.md"
( PATH="$tmp/bin:$PATH"; out close 1 --file "$tmp/midnight.md" >/dev/null )
check "a close earlier than its open is stamped +1d" \
  1 "$(grep -c '^- \[x\] 1 · .*(23:58→00:02+1d)$' "$tmp/midnight.md")"

# --- skip ----------------------------------------------------------------------

s=$(out skip 3 "small lane" --file "$g"); src=$?
check_rc "skip exits ok" 0 "$src"
check "skip marks the phase completed with its reason" \
  1 "$(line 3 | grep -c '^- \[x\] 3 · .* skipped (small lane)$')"
check "skip tells the mirror what to set" completed "$(printf '%s' "$s" | jq -r '.mirror')"
check_rc "skip refuses an open phase" 1 "$(out open 4 --file "$g" >/dev/null; rc skip 4 "small lane" --file "$g")"
check_rc "skip needs a reason" 2 "$(rc skip 3 --file "$g")"

# A refusal is on stderr as well as in the JSON on stdout: `| jq -r .mirror` over
# the stdout alone reads a refusal as `null` and exit 0 (ship #407).
sout=$(bash "$m" skip 4 "small lane" --file "$g" 2>"$tmp/skip.err"); src=$?
check "an open phase's refusal is in the JSON error on stdout" \
  "phase 4 is open; close it before skipping it" "$(jq -r .error <<<"$sout")"
check "the same refusal is on stderr" \
  "phase 4 is open; close it before skipping it" "$(cat "$tmp/skip.err")"
check_rc "the refusal exits 1" 1 "$src"

# A grep that fails (exit 2, as against 1 for no match) is a failed read, never a
# clean answer: each guard and the phase lookup answer tooling, not a pass and
# not "a subagent overwrote the Run file".
gshim=$tmp/gshim; mkdir -p "$gshim"
shimgrep() { # shimgrep <text>: a grep that exits 2 on a call whose arguments contain <text>
  printf '#!/bin/sh\ncase "$*" in *"%s"*) exit 2 ;; esac\nexec %s "$@"\n' "$1" "$(command -v grep)" > "$gshim/grep"
  chmod +x "$gshim/grep"
}
gerr() { PATH=$gshim:$PATH bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
grc()  { PATH=$gshim:$PATH bash "$m" "$@" >/dev/null 2>&1; echo $?; }
shimgrep '→'
check_rc "a failing grep in the --tripwires guard is tooling" 2 "$(grc init 310 --scratchpad "$tmp" --tripwires 'x in_progress (10:00→)')"
check "and says which guard could not read" "cannot check --tripwires for the Run file's own state shapes: grep failed" \
  "$(gerr init 311 --scratchpad "$tmp" --tripwires 'x')"
check "and the guard wrote no Run file" "" "$(ls "$tmp/ship-310/run.md" 2>/dev/null)"
sk=$(out init 312 --scratchpad "$tmp" | jq -r '.run_file'); held=$(cat "$sk")
check_rc "a failing grep in the skip reason guard is tooling" 2 "$(grc skip 3 'r (10:00→)' --file "$sk")"
check "and says which guard could not read" "cannot check that reason for the Run file's own state shapes: grep failed" \
  "$(gerr skip 3 'r' --file "$sk")"
check "and the Run file is as it was" "$held" "$(cat "$sk")"
shimgrep ' · '
check_rc "a failing grep reading a phase line is tooling, not a clobbered Run file" 2 "$(grc open 3 --file "$sk")"
check "and says the read failed" "cannot read the phase lines in $sk: grep failed" "$(gerr open 3 --file "$sk")"
rm "$gshim/grep"


# --- timing --------------------------------------------------------------------

# A complete run, stamped by hand so the arithmetic has a known answer.
t=$(out init 300 --scratchpad "$tmp" | jq -r '.run_file')
stamps() { # stamps <file> <phase>=<tail> ...
  local f=$1; shift
  local pair n tail
  for pair in "$@"; do
    n=${pair%%=*}; tail=${pair#*=}
    tail=$tail n=$n awk '
      $0 ~ "^- \\[.\\] " ENVIRON["n"] " · " {
        sub(/^- \[.\] /, ""); sub(/ in_progress \([0-9][0-9]:[0-9][0-9]→\)$/, "")
        while (sub(/ \([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9](\+1d)?\)/, "")) { }
        print "- [x] " $0 " " ENVIRON["tail"]; next
      } { print }' "$f" > "$f.s" && mv "$f.s" "$f"
  done
}
stamps "$t" '0=(10:00→10:05)' '1=(10:05→10:15)' '2=(10:15→10:45)' '4=(10:45→11:00)' \
            '5=(11:00→11:10)' '6=(11:10→11:20)' '7=(11:20→11:50)' '8=(11:50→12:00)'
out skip 3 "small lane" --file "$t" >/dev/null

tj=$(out timing --file "$t")
check "start→PR is phase 0's open to phase 6's close" 80 "$(printf '%s' "$tj" | jq -r '.start_to_pr')"
check "PR→gate is phase 6's close to phase 8's close" 40 "$(printf '%s' "$tj" | jq -r '.pr_to_gate')"
check "a per-phase field is its own range" 30 "$(printf '%s' "$tj" | jq -r '.phases["2"]')"
check "a skipped phase reads skipped, not unverified" skipped "$(printf '%s' "$tj" | jq -r '.phases["3"]')"
check "the row is the merge summary's line" \
  'start→PR 80m · PR→gate 40m · per phase: 0 5 · 1 10 · 2 30 · 3 skipped · 4 15 · 5 10 · 6 10 · 7 30 · 8 10' \
  "$(printf '%s' "$tj" | jq -r '.row')"
check_rc "timing exits ok" 0 "$(rc timing --file "$t")"

# A re-opened phase sums its ranges, and a range stamped +1d crossed midnight.
stamps "$t" '2=(10:15→10:45) (11:00→11:05)' '1=(23:58→00:12+1d)'
tj=$(out timing --file "$t")
check "a re-opened phase sums its ranges" 35 "$(printf '%s' "$tj" | jq -r '.phases["2"]')"
check "a +1d close crossed midnight" 14 "$(printf '%s' "$tj" | jq -r '.phases["1"]')"

# A rebuilt file: the ranges the rebuild could not recover are absent, so the
# aggregate that needs one of them has no endpoint.
r=$(out init 301 --scratchpad "$tmp" | jq -r '.run_file')
stamps "$r" '0=(09:00→09:10)' '6=' '8=(10:00→10:30)'
rj=$(out timing --file "$r")
check "an aggregate missing an endpoint is unverified" \
  unverified "$(printf '%s' "$rj" | jq -r '.start_to_pr')"
check "so is the aggregate on the other side of it" \
  unverified "$(printf '%s' "$rj" | jq -r '.pr_to_gate')"
check "a phase closed with no range is unverified" \
  unverified "$(printf '%s' "$rj" | jq -r '.phases["6"]')"
check "a phase that does carry a range is still a number" \
  10 "$(printf '%s' "$rj" | jq -r '.phases["0"]')"


# --- rebuild -------------------------------------------------------------------

# The clobber recovery: a Run file overwritten by a subagent is rebuilt in
# place, closed phases whose range the transcript still holds carrying it and
# the rest carrying none, and the phase that was running re-opened at the clock.
mkdir -p "$tmp/ship-400"
echo 'a subagent wrote its scratch here' > "$tmp/ship-400/run.md"
b=$(out init 400 --scratchpad "$tmp" --rebuild \
      --state '0=done:09:00→09:10' --state '1=done' --state '3=skipped:small lane' --state '4=open')
check_rc "a rebuild over an existing file is ok" 0 "$?"
check "the rebuilt file is the ten items again" \
  10 "$(grep -c '^- \[.\] [0-9] · ' "$tmp/ship-400/run.md")"
rb="$tmp/ship-400/run.md"
check "a recovered range is written as it was" \
  1 "$(grep -c '^- \[x\] 0 · .*(09:00→09:10)$' "$rb")"
check "a closed phase with no recovered range carries none" \
  1 "$(grep -c '^- \[x\] 1 · [^(]*$' "$rb")"
check "a skipped phase carries its reason" \
  1 "$(grep -c '^- \[x\] 3 · .* skipped (small lane)$' "$rb")"
check "the phase that was running is re-opened at the clock" \
  1 "$(grep -c '^- \[ \] 4 · .* in_progress ([0-9][0-9]:[0-9][0-9]→)$' "$rb")"
check "the rebuilt file still holds exactly one open phase" \
  1 "$(grep -c 'in_progress ([0-9][0-9]:[0-9][0-9]→)$' "$rb")"
check "the run file is reported back" "$rb" "$(printf '%s' "$b" | jq -r '.run_file')"

check_rc "two open states are refused" 1 \
  "$(rc init 401 --scratchpad "$tmp" --state 2=open --state 5=open)"
# The 3/4 overlap is the one pair of open phases a run holds, so it is the one
# pair a rebuild records; any other pair still contradicts the one-open rule.
ov=$(out init 406 --scratchpad "$tmp" --state 0=done --state 1=done --state 2=done --state 3=open --state 4=open | jq -r .run_file)
check "a rebuild records the 3/4 overlap as two open phases" \
  2 "$(grep -c '^- \[ \] [34] · .* in_progress ([0-9][0-9]:[0-9][0-9]→)$' "$ov")"
check_rc "the overlap given in the other order is accepted" 0 \
  "$(rc init 407 --scratchpad "$tmp" --state 4=open --state 3=open)"
check_rc "open 5 over the rebuilt overlap is still refused" 1 "$(rc open 5 --file "$ov")"
check_rc "two open states other than 3 and 4 are refused" 1 \
  "$(rc init 408 --scratchpad "$tmp" --state 3=open --state 5=open)"
check_rc "3 and 4 with a third open are refused" 1 \
  "$(rc init 409 --scratchpad "$tmp" --state 3=open --state 4=open --state 5=open)"
check "the overlap refusal still names the count" \
  "a Run file holds one open phase, or 3 and 4 together; 2 were given" \
  "$(err init 410 --scratchpad "$tmp" --state 2=open --state 4=open)"

# A new run of an issue whose earlier run stopped replaces the record; a resumed
# run reads it. The refusal names both, and the replacement is a bare rebuild.
out init 411 --scratchpad "$tmp" >/dev/null
out close 0 --file "$tmp/ship-411/run.md" >/dev/null
check "an existing Run file is refused with both ways forward" \
  "Run file exists: $tmp/ship-411/run.md: a resumed run reads that record, and a new run of an issue whose earlier run stopped replaces it with \`run-file init 411 --rebuild\`" \
  "$(err init 411 --scratchpad "$tmp")"
check_rc "an existing Run file is refused with exit 1" 1 "$(rc init 411 --scratchpad "$tmp")"
nr=$(out init 411 --scratchpad "$tmp" --rebuild)
check "a bare rebuild is a fresh record with phase 0 open" \
  "0 in_progress 1 0" \
  "$(jq -r '[.opened, .mirror] | join(" ")' <<<"$nr") $(grep -c 'in_progress' "$tmp/ship-411/run.md") $(grep -c '^- \[x\]' "$tmp/ship-411/run.md")"

check_rc "a state spec that does not parse is malformed" 2 \
  "$(rc init 402 --scratchpad "$tmp" --state 2=running)"
check_rc "a state naming no phase of the ten is malformed" 2 \
  "$(rc init 403 --scratchpad "$tmp" --state 12=done)"


# --- adversarial: a range shape that is text and not a stamp ---------------------

# Ten lines of regex read as correct and answer wrong on the input nobody wrote
# a case for: every field here can carry the stamp's own shape.
shapes='--tripwires cannot carry the Run file'"'"'s own state shapes ((HH:MM→HH:MM), in_progress (HH:MM→), skipped (<reason>)): a phase line reads them as state'
check "init refuses a profile tail carrying a range" "$shapes" \
  "$(err init 499 --scratchpad "$tmp" --tripwires 'held (09:00→17:00)')"
check_rc "a tail carrying a range is malformed" 2 \
  "$(rc init 498 --scratchpad "$tmp" --tripwires 'held (09:00→17:00)')"
# A tail can imitate any shape the mechanic writes, not just the one at the end:
# a range behind a `skipped (...)` the strip would expose, a half-open stamp
# `open_phase` would read as an active phase, and the skip suffix `item` strips.
check "init refuses a tail carrying a range behind a skipped suffix" "$shapes" \
  "$(err init 497 --scratchpad "$tmp" --tripwires 'held (09:00→17:00) skipped (profile)')"
check "init refuses a tail carrying the open marker" "$shapes" \
  "$(err init 496 --scratchpad "$tmp" --tripwires 'x in_progress (09:00→)')"
check "init refuses a tail carrying a skip suffix" "$shapes" \
  "$(err init 495 --scratchpad "$tmp" --tripwires 'manual skipped (small lane)')"

# A skip reason is free text the profile does not supply, so it can still carry
# a range shape; it is wording, and the strip takes the whole reason with it.
a=$(out init 500 --scratchpad "$tmp" | jq -r '.run_file')
out skip 3 'blocked (10:00→10:30)' --file "$a" >/dev/null
check "a range inside a skip reason is wording, not time" \
  skipped "$(out timing --file "$a" | jq -r '.phases["3"]')"

# The design and plan sit below the checklist in the same file, so a line of
# the checklist's shape can appear there. One phase, one line: the first.
b=$(out init 501 --scratchpad "$tmp" "${done_below2[@]}" | jq -r '.run_file')
out open 2 --file "$b" >/dev/null
sed 's|^\(- \[ \] 2 · .*\) in_progress ([0-9][0-9]:[0-9][0-9]→)$|\1 (10:00→10:30)|; s|^- \[ \] 2|- [x] 2|' "$b" > "$b.x" && mv "$b.x" "$b"
printf -- '- [x] 2 · note copied into the plan (00:00→00:01)\n' >> "$b"
check "a line of the same shape below the checklist does not win" \
  30 "$(out timing --file "$b" | jq -r '.phases["2"]')"

# --- skip and open against a phase that already carries a state ----------------

c=$(out init 502 --scratchpad "$tmp" "${done_below5[@]}" | jq -r '.run_file')
out open 5 --file "$c" >/dev/null; out close 5 --file "$c" >/dev/null
check "skip on a phase that has run is refused" \
  "phase 5 has already run; it cannot be skipped" "$(err skip 5 oops --file "$c")"
check_rc "skip on a phase that has run exits 1" 1 "$(rc skip 5 oops --file "$c")"

out skip 6 'small lane' --file "$c" >/dev/null
# A second skip replaces the reason and leaves the phase skipped, so the cases
# below pin the new reason, the first skip's JSON shape and the refusals a
# re-stamp does not relax.
check "a re-stamp answers with the first skip's shape and the new reason" \
  'skipped completed phase 4 reached a new directory' \
  "$(out skip 6 'phase 4 reached a new directory' --file "$c" \
       | jq -r '[.state, .mirror, .reason] | join(" ")')"
check_rc "a re-stamp exits 0" 0 "$(rc skip 6 'phase 4 reached a new directory' --file "$c")"
check "the re-stamped line carries the new reason alone" \
  '- [x] 6 · Open PR: non-draft, Conventional-Commit title, Closes, reflect on the issue skipped (phase 4 reached a new directory)' \
  "$(grep '^- \[.\] 6 · ' "$c")"
check "a re-stamp whose reason closes the wrapper into a state shape is refused" \
  "that reason leaves the phase line ending in one of the Run file's own state shapes; reword it" \
  "$(err skip 6 'x) in_progress (10:00→' --file "$c")"
check "timing reads the re-stamped phase as it reads any skipped phase" \
  skipped "$(out timing --file "$c" | jq -r '.phases["6"]')"
# The small lane revokes one way only, so a skipped phase can come back.
out open 6 --file "$c" >/dev/null
check "re-opening a skipped phase drops the skip" \
  1 "$(line6=$(grep '^- \[.\] 6 · ' "$c"); printf '%s' "$line6" | grep -c 'Closes, reflect on the issue in_progress ([0-9][0-9]:[0-9][0-9]→)$')"

# --- timing on the file the rebuild actually wrote -------------------------------

check "an aggregate over a rebuilt file is unverified where a range was lost" \
  unverified "$(out timing --file "$rb" | jq -r '.start_to_pr')"
check "a range the rebuild recovered is still counted" \
  10 "$(out timing --file "$rb" | jq -r '.phases["0"]')"
check "the phase re-opened at the rebuild has no range yet" \
  unverified "$(out timing --file "$rb" | jq -r '.phases["4"]')"


check "skip on a phase rebuilt as done, which carries no range, is refused" \
  "phase 2 has already run; it cannot be skipped" \
  "$(rb2=$(out init 503 --scratchpad "$tmp" --state 2=done | jq -r '.run_file'); err skip 2 oops --file "$rb2")"

check "a --state naming the same phase twice is refused" \
  '--state names phase 0 twice' \
  "$(err init 504 --scratchpad "$tmp" --state 0=done --state 0=open)"
check_rc "a --state naming the same phase twice is malformed" 2 \
  "$(rc init 505 --scratchpad "$tmp" --state 0=done --state 0=open)"


# One phase, one line, for the open-phase check too: a line of the checklist's
# shape copied into the design and plan is not phase 7 going open.
o=$(out init 506 --scratchpad "$tmp" "${done_below2[@]}" | jq -r '.run_file')
printf -- '- [ ] 7 · a line copied into the plan in_progress (10:00→)\n' >> "$o"
check_rc "a copied open line below the checklist does not block an open" 0 \
  "$(rc open 2 --file "$o")"


# The clock is numeric: `in_progress (ab:cd→)` is prose, so `close` refuses it
# rather than rewriting the line as a range.
n=$(out init 507 --scratchpad "$tmp" | jq -r '.run_file')
sed 's|^\(- \[ \] 2 · .*\)$|\1 in_progress (ab:cd→)|' "$n" > "$n.x" && mv "$n.x" "$n"
check "a non-numeric clock is not an open phase" \
  "phase 2 is not open" "$(err close 2 --file "$n")"


# A reason is free text, and `render` wraps it: one that closes the wrapper
# early would leave the line ending in a state shape, which `open_phase` reads
# as an active phase and `close` rewrites.
w=$(out init 508 --scratchpad "$tmp" | jq -r '.run_file')
check "a reason that closes the wrapper and ends in a state shape is refused" \
  "that reason leaves the phase line ending in one of the Run file's own state shapes; reword it" \
  "$(err skip 3 'x) in_progress (10:00→' --file "$w")"
check_rc "such a reason is malformed" 2 "$(rc skip 3 'x) in_progress (10:00→' --file "$w")"
check "the same reason is refused through --state" 2 \
  "$(rc init 509 --scratchpad "$tmp" --state '3=skipped:x) in_progress (10:00→')"
check "a phase the refused skip touched is untouched" \
  1 "$(grep -c '^- \[ \] 3 · [^(]*$' "$w")"

# A phase is one line, so a reason that spans two would split its line and leave
# the item's own text loose in the file.
nl=$(printf 'small lane\nheld (10:00→10:30)')
held=$(cat "$w")
check "a reason carrying a newline is refused" \
  "a phase is one line: that reason carries a newline; reword it" \
  "$(err skip 3 "$nl" --file "$w")"
check_rc "a multi-line reason is malformed" 2 "$(rc skip 3 "$nl" --file "$w")"
check "the refused reason left the Run file untouched" "$held" "$(cat "$w")"

# init decides every state before it writes, so a rebuild refused on its reason
# leaves the record it was asked to recover exactly as it was.
v=$(out init 510 --scratchpad "$tmp" "${done_below4[@]}" | jq -r '.run_file')
out open 4 --file "$v" >/dev/null
was=$(cat "$v")
check_rc "a rebuild whose reason ends in a state shape is malformed" 2 \
  "$(rc init 510 --scratchpad "$tmp" --rebuild --state '3=skipped:x) in_progress (10:00→')"
check "the refused rebuild leaves the Run file it was asked to recover" \
  "$was" "$(cat "$v")"

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
  "no Run file at $tmp/ship-nothing-here/run.md: check that path first; if it is the right one, a subagent removed the Run file; rebuild it with \`run-file init <issue> --rebuild [--scratchpad <dir>]\`, re-passing the --tripwires, --verifications, --reviewers and --legs the run began with and one --state per phase the transcript accounts for (open for the one that was running, or 3 and 4 both open if they overlapped, no invented range), then log what was lost in the deviations log" \
  "$(err close 4 --issue nothing-here --scratchpad "$tmp")"

# With no --scratchpad the record root is the git common dir's, so a TMPDIR no
# longer decides where a run looks: the lookup lands under the checkout's .git
# (`tests/run-file-record.test.sh` proves the round trip) and names that path.
common=$(git rev-parse --path-format=absolute --git-common-dir)
check "--scratchpad defaults to the git common dir, not the OS temp dir" \
  "no Run file at $common/ship/ship-218/run.md: check that path first; if it is the right one, a subagent removed the Run file; rebuild it with \`run-file init <issue> --rebuild [--scratchpad <dir>]\`, re-passing the --tripwires, --verifications, --reviewers and --legs the run began with and one --state per phase the transcript accounts for (open for the one that was running, or 3 and 4 both open if they overlapped, no invented range), then log what was lost in the deviations log" \
  "$(TMPDIR=$tmp err timing --issue 218)"

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
out open 4 --file "$q" >/dev/null; qout close 4 --file "$q" >/dev/null
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
  'phase 2 is neither closed nor skipped. If it ran: `run-file next 2`, `run-file close 2`, then note in the deviations log that its stamp is the recovery time, so its minutes and any start→PR or PR→gate figure it bounds reflect the recovery, plus when it really ran if the transcript holds that. If it did not run: `run-file skip 2 <reason>`. Then retry `run-file open 4`, which names the next such phase if any.' \
  "$(err next 4 --file "$z")"
check_rc "a refused next exits 1" 1 "$(rc next 4 --file "$z")"
check "a refused next wrote nothing, not even the close" "$held" "$(cat "$z")"
check_rc "next needs a phase number" 2 "$(rc next --file "$z")"
check_rc "next with a flag as the phase is malformed" 2 "$(rc next --x --file "$z")"

out close 1 --file "$z" >/dev/null
check "next with nothing open points at open" \
  'no phase is open; use `run-file open 2`' "$(err next 2 --file "$z")"
check_rc "next with nothing open exits 1" 1 "$(rc next 2 --file "$z")"

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


finish
