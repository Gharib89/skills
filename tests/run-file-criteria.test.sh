#!/usr/bin/env bash
# The clean gate holds on a checkbox criterion the run did not meet. `init
# --criteria` records the claimed issue's checkbox lines as `## Criteria`, the
# run attests each as a `Criterion <n>:` line, and `gate clean` reads both; a
# reviewer round re-raising a declined finding cannot settle on `tree unchanged`.
# Driven at the run-file CLI over scratch records, the way run-file-clean is.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
m=${RUN_FILE_MECHANIC:-$PWD/skills/ship/scripts/run-file.sh}
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/docs/agents" "$tmp/records/ship-crit"
git init -q "$repo"
head=abcdef0123456789
f="$tmp/records/ship-crit/run.md"
ci="$tmp/ci.json"
profile="$repo/docs/agents/ship.md"

# --- init --criteria --------------------------------------------------------------
body="$tmp/body.md"
cat > "$body" <<'BODY'
## What to build

- [ ] not a criterion, but a checkbox line is one wherever it sits

## Acceptance criteria

- [ ] first criterion
  - [x] a nested checked one: with a colon
* [ ] third, starred
+ [x] fourth, plus
12. [ ] fifth, numbered
3) [ ] sixth, numbered with a paren

```
- [ ] inside a fence is an example, not a criterion
```

> - [ ] quoted, not a criterion
-[ ] no space after the marker
- [ ]no space after the box
- plain bullet, no box
- [ ]
BODY
run=$(bash "$m" init crit-a --scratchpad "$tmp/init" --criteria "$body" | jq -r .run_file)
check "init records the unfenced checkbox lines in order" \
  '- 1: not a criterion, but a checkbox line is one wherever it sits
- 2: first criterion
- 3: a nested checked one: with a colon
- 4: third, starred
- 5: fourth, plus
- 6: fifth, numbered
- 7: sixth, numbered with a paren' \
  "$(awk '/^## Criteria/ { f = 1; next } /^## / { f = 0 } f && /^- /' "$run")"
check "init puts the criteria before the design and plan" \
  true "$(awk '/^## Criteria/ { c = NR } /^## Design and plan/ { d = NR } END { print (c > 0 && c < d) ? "true" : "false" }' "$run")"
run=$(printf '%s\n' '- [ ] from stdin' | bash "$m" init crit-b --scratchpad "$tmp/init" --criteria - | jq -r .run_file)
check "init reads the criteria text from stdin on -" '- 1: from stdin' "$(grep '^- 1: ' "$run")"
run=$(printf '%s\n' 'no boxes at all' | bash "$m" init crit-c --scratchpad "$tmp/init" --criteria - | jq -r .run_file)
check "init writes no Criteria section when the text has no checkbox" 0 "$(grep -c '^## Criteria' "$run")"
check "init without --criteria answers with the keys it always did" 'id,items,mirror,opened,run_file,scratch' \
  "$(bash "$m" init crit-d --scratchpad "$tmp/init" | jq -r 'keys | join(",")')"
out=$(bash "$m" init crit-e --scratchpad "$tmp/init" --criteria "$tmp/missing.md" 2>&1); rc=$?
check_rc "init refuses a missing criteria file as tooling" 2 "$rc"
check "init names the criteria file it could not read" true \
  "$(if grep -Fq "cannot read the criteria text at $tmp/missing.md" <<<"$out"; then echo true; else echo false; fi)"
check "init leaves no record behind a refused criteria file" false "$(if [ -e "$tmp/init/ship-crit-e" ]; then echo true; else echo false; fi)"
out=$(printf '%s\n' null | bash "$m" init crit-f --scratchpad "$tmp/init" --criteria - 2>&1); rc=$?
check_rc "init refuses the text null, a failed read of the issue body, as tooling" 2 "$rc"
check "init names the null criteria text" true \
  "$(if grep -Fq 'the criteria text is null' <<<"$out"; then echo true; else echo false; fi)"
check "init leaves no record behind null criteria text" false "$(if [ -e "$tmp/init/ship-crit-f" ]; then echo true; else echo false; fi)"
for empty in '' '   '; do
  run=$(printf '%s\n' "$empty" | bash "$m" init crit-g --scratchpad "$tmp/init" --rebuild --criteria - | jq -r .run_file)
  check "init records no criteria for an empty issue body [$empty]" 0 "$(grep -c '^## Criteria' "$run")"
done

# --- gate clean -------------------------------------------------------------------
base() {
  cat > "$profile" <<'PROFILE'
## CI
Legs:
  test: prove the change

## Reviewers
### primary
Trigger: on-request
Fallback-for: None.

## Verification
None.
PROFILE
  cat > "$f" <<'RUN'
# ship run
## Criteria

- 1: first criterion
- 2: second: with a colon
- 3: third criterion

## Local gate
- 10:00 abcdef0123456789 pass {"tests":"pass","secrets":"pass"}
## Review evidence
Round: primary 1: all dispositioned
Stop: primary: tree unchanged at abcdef0123456789
Criterion 1: met: tests/run-file-criteria.test.sh case 1
Criterion 2: met: grep shows it
Criterion 3: met: probe output
RUN
  printf '%s\n' '{"status":"green","head_sha":"abcdef0123456789","checks":[{"name":"test","status":"success"}],"legs":["test"],"missing_legs":[],"failing":[],"non_leg_failing":[],"unlisted":[],"waited_s":0}' > "$ci"
}
call() { (cd "$repo" && bash "$m" gate clean "$ci" --head "$head" --file "$f" 2>"$tmp/err"); }
held() {
  local name=$1 reason=$2 answer rc
  answer=$(call); rc=$?
  check_rc "$name refuses" 1 "$rc"
  check "$name names its hold" true "$(jq -r --arg r "$reason" '.clean == false and (.held_by | index($r) != null)' <<<"$answer")"
  check "$name reports its hold on stderr" true "$(if grep -Fq -- "$reason" "$tmp/err"; then echo true; else echo false; fi)"
}
clean() {
  local name=$1 answer rc
  answer=$(call); rc=$?
  check_rc "$name exits clean" 0 "$rc"
  check "$name has no holds" '{"clean":true,"held_by":[]}' "$(jq -c . <<<"$answer")"
}
change_run() { sed "$1" "$f" > "$f.new" && mv "$f.new" "$f"; }

base; clean 'every criterion met'
base; change_run 's/^Criterion 2: met: grep shows it/Criterion 2: not met: the host action needs a human/'
held 'a not-met criterion' 'criterion 2: not met: the host action needs a human'
base; change_run '/^Criterion 3: /d'
held 'a criterion with no line' 'criterion 3: no line'
base; change_run '/^Criterion [23]: /d; s/^Criterion 1: met: .*/Criterion 1: not met: later/'
check "one hold per criterion that is not met or has no line" 3 "$(call | jq '.held_by | length')"
base; change_run 's/^Criterion 1: met: .*/Criterion 1: not met: first try/'; printf '%s\n' 'Criterion 1: met: fixed since, test green' >> "$f"
clean 'a not-met line a later met line replaced'
base; change_run 's/^Criterion 1: met: .*/Criterion 1: met:/'
held 'a met line with no proof' 'criterion 1: met:'
base; change_run 's/^Criterion 1: met: .*/Criterion 1: nearly/'
held 'a line that is neither met nor not met' 'criterion 1: nearly'
# A fenced example cannot satisfy a criterion.
base; change_run '/^Criterion 3: /d'; printf '%s\n' '```' 'Criterion 3: met: an example in a fence' '```' >> "$f"
held 'a met line inside a fence' 'criterion 3: no line'
# No Criteria section is the run before this record existed: judged as it always was.
base; change_run '/^## Criteria/,/^- 3: /d; /^Criterion [123]: /d'
clean 'a run with no Criteria section'

# --- a re-raised declined finding -------------------------------------------------
base; change_run 's/^Round: primary 1: .*/Round: primary 1: one finding declined\nRound: primary 2: re-raised declined: the retry guard, no new finding/'
held 'a tree-unchanged stop after a re-raised declined finding' 'reviewer primary: tree unchanged with a re-raised declined finding, which stops on cap'
base; change_run 's/^Round: primary 1: .*/Round: primary 1: one finding declined\nRound: primary 2: re-raised declined: the retry guard/; s/^Stop: primary: .*/Stop: primary: cap/'
held 'the cap stop that records it' 'reviewer primary: cap'
base; change_run 's/^Round: primary 1: .*/Round: primary 1: no finding was re-raised, all fixed/'
clean 'a round saying a finding was not re-raised'
base; change_run 's/^Round: primary 1: .*/Round: primary 1: no finding re-raised declined: all fixed/'
clean 'a round mentioning the marker mid-sentence'
# A re-raise cap owes no fallback. Only the last-round case is red on the code before the re-raise exclusion; the other guards it.
cap_primary_settle_fallback() {
  sed -i 's/^Fallback-for: None\.$/Fallback-for: None.\n### fallback\nTrigger: on-request\nFallback-for: primary/' "$profile"
  change_run 's/^Stop: primary: tree unchanged at abcdef0123456789/Stop: primary: cap/'
  printf '%s\n' 'Round: fallback 1: all dispositioned' 'Stop: fallback: tree unchanged at abcdef0123456789' >> "$f"
}
base; sed -i 's/^Trigger: on-request$/Trigger: on-request\nCap: 2/' "$profile"; cap_primary_settle_fallback
change_run 's/^Round: primary 1: .*/Round: primary 1: fixes pushed\nRound: primary 2: fixes pushed again/'
clean 'a capped primary a fallback settled'
change_run 's/^Round: primary 2: .*/Round: primary 2: re-raised declined: the retry guard/'
held 'a re-raise cap in the last round of the primary Cap, a fallback settled' 'reviewer primary: cap'
base; sed -i 's/^Trigger: on-request$/Trigger: on-request\nCap: 3/' "$profile"; cap_primary_settle_fallback
change_run 's/^Round: primary 1: .*/Round: primary 1: one finding declined\nRound: primary 2: re-raised declined: the retry guard/'
held 'a re-raise cap before the primary Cap is spent, a fallback settled' 'reviewer primary: cap'

finish
