#!/usr/bin/env bash
# #894: an attended run cannot reach the merge-gate summary with a criterion the
# clean gate would hold. `close 5` refuses a `## Criteria` entry with no
# `Criterion <n>:` line or a placeholder `not met`, and `gate summary <pr>` gives
# the summary's two lines from `gate clean`'s own evaluation of the saved
# `ci-wait.json` and the head `read-pr` returns.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
bin=$tmp/bin repo=$tmp/repo
mkdir -p "$bin" "$repo/docs/agents"
cp -r skills/ship/scripts/run-file.sh skills/ship/scripts/_lib.sh skills/ship/scripts/lib "$bin/"
git init -q "$repo"
head=abcdef0123456789
# read-pr's stub answers the head the test sets, or fails when the file is absent.
cat > "$bin/read-pr.sh" <<STUB
#!/usr/bin/env bash
[ -f "$tmp/pr-head" ] || exit 2
printf '{"head_sha":"%s"}\n' "\$(cat "$tmp/pr-head")"
STUB
chmod +x "$bin/read-pr.sh"
printf '%s\n' "$head" > "$tmp/pr-head"
cat > "$repo/docs/agents/ship.md" <<'PROFILE'
## CI
Legs:
  test: prove the change

## Reviewers
### primary
Trigger: on-request
Fallback-for: None.
PROFILE

n=0
rf=""
# One Run file per case, with phase 5 open and two criteria.
fresh() {
  n=$((n + 1))
  rf=$(printf '%s\n' '- [ ] first' '- [ ] second' \
    | bash "$bin/run-file.sh" init "c$n" --scratchpad "$tmp/sp" --criteria - \
        --state 0=done --state 1=done --state 2=done --state 3=done --state 4=done --state 5=open | jq -r .run_file)
}
add() { printf '%s\n' "$@" >> "$rf"; }
call() { out=$(cd "$repo" && bash "$bin/run-file.sh" "$@" 2>"$tmp/err"); status=$?; err=$(jq -r '.error // empty' <<<"$out" 2>/dev/null); }
has() { case $2 in *"$1"*) echo yes ;; *) echo no ;; esac; }
refused() { # refused <case> <fragment>
  check_rc "$1: exits 1" 1 "$status"
  check "$1: names it" yes "$(has "$2" "$err")"
  check "$1: leaves the record as it was" "$held" "$(cat "$rf")"
}

# --- close 5 ---------------------------------------------------------------------

fresh; held=$(cat "$rf"); call close 5 --file "$rf"
refused "no Criterion line at all" 'criterion 1 has no line'
check "the same refusal names the other entry" yes "$(has 'criterion 2 has no line' "$err")"

fresh; add 'Criterion 1: met: tests/x.test.sh green'; held=$(cat "$rf"); call close 5 --file "$rf"
refused "one entry without a line" 'criterion 2 has no line'
check "and not the one that has it" no "$(has 'criterion 1' "$err")"

for w in pending TODO tbd later 'Pending, later.' wip; do
  fresh; add 'Criterion 1: met: ok' "Criterion 2: not met: $w"; held=$(cat "$rf"); call close 5 --file "$rf"
  refused "a placeholder reason ($w)" 'criterion 2 is'
done

fresh; add 'Criterion 1: met: ok' 'Criterion 2: not met: pending' 'Criterion 2: not met: CI is red until phase 8 ci-wait answers green'; call close 5 --file "$rf"
check_rc "a real reason after a placeholder: exits ok" 0 "$status"
check "and closes the phase" completed "$(jq -r .mirror <<<"$out")"

fresh; add 'Criterion 1: met: ok' 'Criterion 2: not met: pending' 'Criterion 2: met: later proof'; call close 5 --file "$rf"
check_rc "a met line after a placeholder: exits ok" 0 "$status"

fresh; add 'Criterion 1: met: ok' 'Criterion 2: not met: the phase 7 round fixes the wording, which phase 7 settles'; call close 5 --file "$rf"
check_rc "a not met naming its settling step: exits ok" 0 "$status"

fresh; add 'Criterion 1: met: ok' 'Criterion 2: not met:'; held=$(cat "$rf"); call close 5 --file "$rf"
refused "a hand-written line gate clean cannot read" 'criterion 2 has a line gate clean cannot read'

for w in open unknown '...' '?'; do
  fresh; add 'Criterion 1: met: ok' "Criterion 2: not met: $w"; held=$(cat "$rf"); call close 5 --file "$rf"
  refused "a placeholder reason ($w)" 'criterion 2 is'
done

fresh; add 'Criterion 1: met: ok' 'Criterion 2: not met: pending review of the phase 7 reply, which phase 7 settles'; call close 5 --file "$rf"
check_rc "a real reason that opens with a placeholder word: exits ok" 0 "$status"

# A `- N:` line outside `## Criteria` is no entry.
fresh; add 'Criterion 1: met: ok' 'Criterion 2: met: ok' '## Deviations log' '- 3: a decoy, not a criterion'; call close 5 --file "$rf"
check_rc "a numbered line outside Criteria is not an entry" 0 "$status"

# close 5 reads the unfenced text gate clean reads: a fenced example is no line, no entry.
fresh; add 'Criterion 1: met: ok' '```' 'Criterion 2: met: a pasted example' '```'; held=$(cat "$rf"); call close 5 --file "$rf"
refused "a Criterion line inside a fence" 'criterion 2 has no line'
fresh; add 'Criterion 1: met: ok' 'Criterion 2: met: ok' '```' '## Criteria' '- 3: a pasted example' '```'; call close 5 --file "$rf"
check_rc "a fenced Criteria entry is no entry" 0 "$status"

# `next 5` closes phase 5 through the same gate.
fresh; held=$(cat "$rf"); call next 6 --file "$rf"
refused "next over phase 5 with no Criterion lines" 'criterion 1 has no line'

n=$((n + 1))
rf=$(bash "$bin/run-file.sh" init "c$n" --scratchpad "$tmp/sp" --state 0=done --state 1=done --state 2=done --state 3=done --state 4=done --state 5=open | jq -r .run_file)
call close 5 --file "$rf"
check_rc "a Run file with no Criteria section is not refused" 0 "$status"

# A reason written at close 5 and replaced later reads as met in gate clean; one
# never replaced holds it.
cat > "$tmp/ci.json" <<CI
{"status":"green","head_sha":"$head","checks":[{"name":"test","status":"success"}],"legs":["test"],"missing_legs":[],"failing":[],"non_leg_failing":[],"unlisted":[],"waited_s":0}
CI
fresh; add 'Criterion 1: met: ok' 'Criterion 2: not met: waits on phase 7 round 1'
add 'Round: primary 1: clean' "Stop: primary: tree unchanged at $head" '## Local gate' "- 10:00 $head pass {\"secrets\":\"pass\"}"
call gate clean "$tmp/ci.json" --head "$head" --file "$rf"
check "a surviving not met holds gate clean" true "$(jq -r '.held_by | index("criterion 2: not met: waits on phase 7 round 1") != null' <<<"$out")"
add 'Criterion 2: met: round 1 fixed it'
call gate clean "$tmp/ci.json" --head "$head" --file "$rf"
check "the later met line replaces it" true "$(jq -r '.clean' <<<"$out")"

# --- gate summary ----------------------------------------------------------------

fresh; add 'Criterion 1: met: ok' 'Criterion 2: not met: waits on phase 7 round 1'
add 'Round: primary 1: clean' "Stop: primary: tree unchanged at $head" '## Local gate' "- 10:00 $head pass {\"secrets\":\"pass\"}"
dir=$(dirname "$rf")
call gate summary 7 --file "$rf"
check_rc "no saved ci-wait: exits 2, no verdict" 2 "$status"
check "and names the step to run" yes "$(has "run \`ci-wait 7\`" "$err")"

cp "$tmp/ci.json" "$dir/ci-wait.json"
rm "$tmp/pr-head"
call gate summary 7 --file "$rf"
check_rc "an unreadable PR: exits 2, no verdict" 2 "$status"
check "and names read-pr" yes "$(has 'run `read-pr 7`' "$err")"
chmod +x "$bin/read-pr.sh"
printf '%s\n' "$head" > "$tmp/pr-head"

call gate summary 7 --file "$rf"
summary=$out status_summary=$status
check "a held gate writes its reasons on stderr, as gate clean does" yes "$(has 'criterion 2: not met: waits on phase 7 round 1' "$(cat "$tmp/err")")"
call gate clean "$tmp/ci.json" --head "$head" --file "$rf"
check_rc "a held gate: summary exits as gate clean does" "$status" "$status_summary"
check_rc "and that is 1" 1 "$status_summary"
check "its held_by is gate clean's" "$(jq -c .held_by <<<"$out")" "$(jq -c .held_by <<<"$summary")"
check "the Unmet criteria line lists the unmet criterion with its text" 'criterion 2 (second): not met: waits on phase 7 round 1' "$(jq -r .unmet_criteria_line <<<"$summary")"
check "the Clean gate held by line lists each reason" 'criterion 2: not met: waits on phase 7 round 1' "$(jq -r .clean_gate_held_by_line <<<"$summary")"
check "it reports the head read-pr returned" "$head" "$(jq -r .head <<<"$summary")"

add 'Criterion 2: met: round 1 fixed it'
call gate summary 7 --file "$rf"
check_rc "a clean gate: exits 0" 0 "$status"
check "its lines read none" "none/none" "$(jq -r '.unmet_criteria_line + "/" + .clean_gate_held_by_line' <<<"$out")"

# The head is the PR's: a Local gate record on an older head does not cover it.
printf '%s\n' 1234567890abcdef > "$tmp/pr-head"
sed "s/$head/1234567890abcdef/" "$tmp/ci.json" > "$dir/ci-wait.json"
call gate summary 7 --file "$rf"
check_rc "a PR head the evidence does not cover: exits 1" 1 "$status"
check "and holds on the stale stop" yes "$(has 'does not cover head 1234567890abcdef' "$(jq -r '.held_by | join(";")' <<<"$out")")"

# A Run file with no `## Criteria`: the gate read none, so the line must not say "none".
printf '%s\n' "$head" > "$tmp/pr-head"
cp "$tmp/ci.json" "$dir/ci-wait.json"
n=$((n + 1))
rf=$(bash "$bin/run-file.sh" init "c$n" --scratchpad "$tmp/sp" --state 0=done | jq -r .run_file)
cp "$tmp/ci.json" "$(dirname "$rf")/ci-wait.json"
call gate summary 7 --file "$rf"
check "no Criteria section: criteria_recorded is false" false "$(jq -r .criteria_recorded <<<"$out")"
check "and the line says unverified, not none" yes "$(has 'unverified: the Run file has no ## Criteria' "$(jq -r .unmet_criteria_line <<<"$out")")"
# A fenced `## Criteria` example is no section: the gate strips fences before it reads.
printf '%s\n' '```' '## Criteria' '- 1: an example' '```' >> "$rf"
call gate summary 7 --file "$rf"
check "a fenced Criteria heading is no section" false "$(jq -r .criteria_recorded <<<"$out")"

# --- no Criteria beside an issue with checkboxes (#933) --------------------------

# A run whose `init` was never given the issue's checkboxes reached its merge gate
# unjudged. With no `## Criteria` and a numbered issue whose body carries
# checkboxes, the summary holds; the issue is read only then.
cat > "$bin/read-issue.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/read-issue.calls"
[ -f "$tmp/issue-body" ] || exit 2
jq -Rs '{number: 9, body: .}' "$tmp/issue-body"
STUB
chmod +x "$bin/read-issue.sh"
printf '%s\n' '## What' '- [ ] first' '- [x] second' '```' '- [ ] an example, not a criterion' '```' > "$tmp/issue-body"
numbered() { # numbered <issue> [criteria]: a run on a numbered issue with phase 5's evidence
  local rf9
  if [ -n "${2:-}" ]; then rf9=$(printf '%s\n' "$2" | bash "$bin/run-file.sh" init "$1" --scratchpad "$tmp/sp" --criteria - --state 0=done | jq -r .run_file)
  else rf9=$(bash "$bin/run-file.sh" init "$1" --scratchpad "$tmp/sp" --state 0=done | jq -r .run_file); fi
  printf '%s\n' 'Round: primary 1: clean' "Stop: primary: tree unchanged at $head" '## Local gate' "- 10:00 $head pass {\"secrets\":\"pass\"}" >> "$rf9"
  cp "$tmp/ci.json" "$(dirname "$rf9")/ci-wait.json"
  printf '%s' "$rf9"
}
: > "$tmp/read-issue.calls"
rf=$(numbered 9)
call gate summary 7 --file "$rf"
check_rc "no Criteria beside an issue with checkboxes: exits 1" 1 "$status"
check "clean is false" false "$(jq -r .clean <<<"$out")"
check "it names the issue, the count and the way to record them" \
  'criteria: the Run file has no ## Criteria but issue #9 has 2 checkboxes; record each with `run-file note Criteria <text>`' \
  "$(jq -r '.held_by[]' <<<"$out")"
check "the Clean gate held by line carries it" yes "$(has 'issue #9 has 2 checkboxes' "$(jq -r .clean_gate_held_by_line <<<"$out")")"
check "the reasons reach stderr as gate clean's do" yes "$(has 'issue #9 has 2 checkboxes' "$(cat "$tmp/err")")"
check "the Unmet criteria line still says unverified" yes "$(has 'unverified: the Run file has no ## Criteria' "$(jq -r .unmet_criteria_line <<<"$out")")"

printf '%s\n' '## What' '- plain bullet, no box' > "$tmp/issue-body"
rf=$(numbered 91)
call gate summary 7 --file "$rf"
check_rc "an issue with no checkboxes holds nothing" 0 "$status"

printf '%s\n' '- [ ] first' > "$tmp/issue-body"
: > "$tmp/read-issue.calls"
rf=$(numbered 92 '- [ ] first')
printf '%s\n' 'Criterion 1: met: ok' >> "$rf"
call gate summary 7 --file "$rf"
check_rc "a recorded Criteria section needs no issue read" 0 "$status"
check "and the issue is not read" 0 "$(wc -l < "$tmp/read-issue.calls" | tr -d ' ')"

rm "$tmp/issue-body"
rf=$(numbered 93)
call gate summary 7 --file "$rf"
check_rc "an issue that cannot be read is no verdict: exits 2" 2 "$status"
check "and it names read-issue" yes "$(has 'run `read-issue 93`' "$err")"

: > "$tmp/read-issue.calls"
rf=$(numbered some-slug)
call gate summary 7 --file "$rf"
check_rc "a slug run has no issue to read" 0 "$status"
check "and none is read" 0 "$(wc -l < "$tmp/read-issue.calls" | tr -d ' ')"

# --- init warns when the criteria were not passed (#933) ------------------------

printf '%s\n' '- [ ] first' '- [ ] second' > "$tmp/issue-body"
warn() { # warn <args>...: init from the fixture repo, its stderr in $tmp/err
  out=$(cd "$repo" && bash "$bin/run-file.sh" init "$@" --scratchpad "$tmp/sp2" 2>"$tmp/err"); status=$?
}
warn 31 --from-profile
check_rc "init still succeeds without --criteria" 0 "$status"
check "a numbered issue with checkboxes and no --criteria draws a warning naming the flag" yes \
  "$(has 'issue #31 has 2 checkboxes but --criteria was not passed' "$(cat "$tmp/err")")"
check "the warning says to re-run the same init with the flags added" yes \
  "$(has 'run the same init again with `--criteria -` and `--rebuild` added' "$(cat "$tmp/err")")"
check "the warning prints no shortened init line to paste" no "$(has 'run-file init 31 --criteria' "$(cat "$tmp/err")")"
check "stdout is still the one JSON answer" 31 "$(jq -r .id <<<"$out")"
warn 32 --from-profile --criteria "$tmp/issue-body"
check "--criteria silences it" "" "$(cat "$tmp/err")"
warn 33
check "a bare init, with no profile to name the host, reads no issue" "" "$(cat "$tmp/err")"
warn some-slug --from-profile
check "a slug run reads no issue" "" "$(cat "$tmp/err")"
printf '%s\n' 'no boxes' > "$tmp/issue-body"
warn 34 --from-profile
check "an issue with no checkboxes draws none" "" "$(cat "$tmp/err")"
rm "$tmp/issue-body"
warn 35 --from-profile
check_rc "an unreadable issue does not stop init" 0 "$status"
check "and draws no warning" "" "$(cat "$tmp/err")"

finish
