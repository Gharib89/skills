#!/usr/bin/env bash
# Split by behaviour from tests/run-file.test.sh: rebuild and re-measure cases.
# The run-file mechanic: the Run file's checklist, its flips and its timing
# arithmetic. Every case drives the mechanic against a scratch directory under
# the OS temp dir; the mechanic reaches no host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/run-file.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT


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

# Two initializers in one clone (#636): the other one's record lands after this
# one found no file but before it wrote. A `mkdir` in front of PATH lands it
# inside that window, so the create itself must refuse an existing file.
race=$tmp/race-bin; mkdir -p "$race"
cat > "$race/mkdir" <<EOF
#!/usr/bin/env bash
"$(command -v mkdir)" "\$@" || exit
[ ! -d "$tmp/ship-412" ] || [ -e "$tmp/ship-412/run.md" ] || printf 'the other run\n' > "$tmp/ship-412/run.md"
EOF
chmod +x "$race/mkdir"
check_rc "a Run file created inside the init window is refused" 1 \
  "$(PATH="$race:$PATH" rc init 412 --scratchpad "$tmp")"
check "and is left as the other run wrote it" 'the other run' "$(cat "$tmp/ship-412/run.md")"
# A line write's temp file is this process's own, so another writer's in-flight
# one is neither overwritten nor moved over the record.
out init 413 --scratchpad "$tmp" >/dev/null
printf 'in flight\n' > "$tmp/ship-413/run.md.t"
out close 0 --file "$tmp/ship-413/run.md" >/dev/null
check "a line write leaves another writer's temp file alone" 'in flight' "$(cat "$tmp/ship-413/run.md.t" 2>/dev/null)"

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


finish
