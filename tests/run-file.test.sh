#!/usr/bin/env bash
# The run-file mechanic: the Run file's checklist, its flips and its timing
# arithmetic. Every case drives the mechanic against a scratch directory under
# the OS temp dir; the mechanic reaches no host and no repo file.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/run-file.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

out()  { bash "$m" "$@" 2>/dev/null; }
err()  { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()   { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

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
- [ ] 7 · Reviewers: copilot (on-request), claude (on-request) to convergence
- [ ] 8 · CI: resolve any conflict, land None green
- [ ] 9 · Merge gate: hard stop for human approval (unattended: summary as PR comment, return)' \
  "$(grep '^- \[ \] ' "$f")"

check "init returns the ten items for the mirror" \
  10 "$(out init 193 --scratchpad "$tmp" | jq '.items | length')"

check "a slug argument names the directory" \
  "$tmp/ship-body-rewrite/run.md" \
  "$(out init body-rewrite --scratchpad "$tmp" | jq -r '.run_file')"

check_rc "init refuses to overwrite an existing Run file" 1 "$(rc init 192 --scratchpad "$tmp")"

# --- open and close ------------------------------------------------------------

g=$(out init 200 --scratchpad "$tmp" | jq -r '.run_file')
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

check "close on a phase that is not open is refused" \
  "phase 7 is not open" "$(err close 7 --file "$g")"
check_rc "close on a phase that is not open exits 1" 1 "$(rc close 7 --file "$g")"

out close 2 --file "$g" >/dev/null
check "close on an already closed phase is refused" \
  "phase 2 is not open" "$(err close 2 --file "$g")"

grep -v '^- \[.\] 8 · ' "$g" > "$tmp/gapped.md"
check "a flip whose line is absent names the line" \
  "no phase 8 line in $tmp/gapped.md" "$(err open 8 --file "$tmp/gapped.md")"
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
# rather than reading as a range that runs backwards.
sed 's|^- \[.\] 1 · \(.*\)|- [ ] 1 · \1 in_progress (23:58→)|' "$g" > "$tmp/midnight.md"
out close 1 --file "$tmp/midnight.md" >/dev/null
check "a close earlier than its open is stamped +1d" \
  1 "$(grep -c '^- \[x\] 1 · .*(23:58→[0-9][0-9]:[0-9][0-9]+1d)$' "$tmp/midnight.md")"

# --- skip ----------------------------------------------------------------------

s=$(out skip 3 "small lane" --file "$g"); src=$?
check_rc "skip exits ok" 0 "$src"
check "skip marks the phase completed with its reason" \
  1 "$(line 3 | grep -c '^- \[x\] 3 · .* skipped (small lane)$')"
check "skip tells the mirror what to set" completed "$(printf '%s' "$s" | jq -r '.mirror')"
check_rc "skip refuses an open phase" 1 "$(out open 4 --file "$g" >/dev/null; rc skip 4 "small lane" --file "$g")"
check_rc "skip needs a reason" 2 "$(rc skip 3 --file "$g")"


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
check "a phase with no range is unverified" unverified "$(printf '%s' "$tj" | jq -r '.phases["3"]')"
check "the row is the merge summary's line" \
  'start→PR 80m · PR→gate 40m · per phase: 0 5 · 1 10 · 2 30 · 3 unverified · 4 15 · 5 10 · 6 10 · 7 30 · 8 10' \
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
  unverified "$(out timing --file "$a" | jq -r '.phases["3"]')"

# The design and plan sit below the checklist in the same file, so a line of
# the checklist's shape can appear there. One phase, one line: the first.
b=$(out init 501 --scratchpad "$tmp" | jq -r '.run_file')
out open 2 --file "$b" >/dev/null
sed 's|^\(- \[ \] 2 · .*\) in_progress ([0-9][0-9]:[0-9][0-9]→)$|\1 (10:00→10:30)|; s|^- \[ \] 2|- [x] 2|' "$b" > "$b.x" && mv "$b.x" "$b"
printf -- '- [x] 2 · note copied into the plan (00:00→00:01)\n' >> "$b"
check "a line of the same shape below the checklist does not win" \
  30 "$(out timing --file "$b" | jq -r '.phases["2"]')"

# --- skip and open against a phase that already carries a state ----------------

c=$(out init 502 --scratchpad "$tmp" | jq -r '.run_file')
out open 5 --file "$c" >/dev/null; out close 5 --file "$c" >/dev/null
check "skip on a phase that has run is refused" \
  "phase 5 has already run; it cannot be skipped" "$(err skip 5 oops --file "$c")"
check_rc "skip on a phase that has run exits 1" 1 "$(rc skip 5 oops --file "$c")"

out skip 6 'small lane' --file "$c" >/dev/null
check "skip on an already skipped phase is refused" \
  "phase 6 is already skipped" "$(err skip 6 'small lane' --file "$c")"
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
o=$(out init 506 --scratchpad "$tmp" | jq -r '.run_file')
printf -- '- [ ] 7 · a line copied into the plan in_progress (10:00→)\n' >> "$o"
check_rc "a copied open line below the checklist does not block an open" 0 \
  "$(rc open 2 --file "$o")"


# The clock is numeric: `in_progress (ab:cd→)` is prose, so `close` refuses it
# rather than rewriting the line as a range.
n=$(out init 507 --scratchpad "$tmp" | jq -r '.run_file')
sed 's|^\(- \[ \] 2 · .*\)$|\1 in_progress (ab:cd→)|' "$n" > "$n.x" && mv "$n.x" "$n"
check "a non-numeric clock is not an open phase" \
  "phase 2 is not open" "$(err close 2 --file "$n")"


finish
