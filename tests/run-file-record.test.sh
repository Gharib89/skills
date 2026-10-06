#!/usr/bin/env bash
# The run-file mechanic's record: where it lives, what init takes from the ship
# profile, the Phase 3 results and the gate record. Driven end to end over a
# fixture repo with a worktree, so the record root is the real `git rev-parse
# --git-common-dir` and not a stand-in; the mechanic reaches no host. The flips
# and the timing arithmetic are `tests/run-file.test.sh`'s.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=$PWD/skills/ship/scripts/run-file.sh
profile=$PWD/tests/fixtures/run-file/ship-profile.md
spaced=$PWD/tests/fixtures/run-file/ship-profile-spaced.md
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

repo=$tmp/repo wt=$tmp/repo.worktrees/feat-7
git init -q -b main "$repo"
g() { git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
g commit -q --allow-empty -m one
first=$(g rev-parse HEAD)
g worktree add -q "$wt" -b feat/x-7
common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
root=$common/ship

# at <dir> <args...>: the mechanic run from a directory, stdout only.
at()    { local d=$1; shift; ( cd "$d" && bash "$m" "$@" 2>/dev/null ); }
inrc()  { local d=$1; shift; ( cd "$d" && bash "$m" "$@" >/dev/null 2>&1 ); echo $?; }
inerr() { local d=$1; shift; ( cd "$d" && bash "$m" "$@" 2>/dev/null ) | jq -r '.error'; }

# --- where the record lives -----------------------------------------------------

session=$tmp/session-scratchpad; mkdir -p "$session"
j=$(at "$wt" init 7)
check "init from a worktree writes under the git common dir" "$root/ship-7/run.md" "$(jq -r .run_file <<<"$j")"
check "init reports the run's scratch directory" "$root/scratch-7" "$(jq -r .scratch <<<"$j")"
check "the scratch directory exists" yes "$([ -d "$root/scratch-7" ] && echo yes || echo no)"
check "--issue from the main checkout resolves the same record" \
  "$root/ship-7/run.md" "$(at "$repo" timing --issue 7 | jq -r .run_file)"
check "--issue from the worktree resolves it too" \
  "$root/ship-7/run.md" "$(at "$wt" timing --issue 7 | jq -r .run_file)"
check_rc "close by --issue from the main checkout exits ok" 0 "$(inrc "$repo" close 0 --issue 7)"
check "the main checkout's tree stays clean" "" "$(git -C "$repo" status --porcelain)"
check "the worktree's tree stays clean" "" "$(git -C "$wt" status --porcelain)"
rm -rf "$session"
check "wiping a session scratchpad leaves the record" \
  "$root/ship-7/run.md" "$(at "$wt" timing --issue 7 | jq -r .run_file)"
check "two issues get distinct scratch directories" \
  "$root/scratch-8" "$(at "$repo" init 8 | jq -r .scratch)"
check "an explicit --scratchpad is the root" \
  "$tmp/sp/scratch-5" "$(at "$repo" init 5 --scratchpad "$tmp/sp" | jq -r .scratch)"
check "an explicit --scratchpad holds the run file too" \
  "$tmp/sp/ship-5/run.md" "$(at "$repo" timing --issue 5 --scratchpad "$tmp/sp" | jq -r .run_file)"

# Outside a checkout there is no root to default to: the refusal names the flag.
nogit=$tmp/nogit; mkdir -p "$nogit"
check_rc "init outside a checkout with no --scratchpad is malformed" 2 \
  "$(GIT_CEILING_DIRECTORIES=$tmp inrc "$nogit" init 9)"
check "the refusal names --scratchpad" \
  "not inside a git checkout: pass --scratchpad <dir>" "$(GIT_CEILING_DIRECTORIES=$tmp inerr "$nogit" init 9)"
check_rc "--issue outside a checkout with no --scratchpad is malformed" 2 \
  "$(GIT_CEILING_DIRECTORIES=$tmp inrc "$nogit" close 0 --issue 9)"

# --- results of the phase 3 verifications ---------------------------------------

rf=$(at "$repo" init 20 --verifications 'github-mechanics, ado-mechanics' | jq -r .run_file)
check "init keeps the checklist line's text" \
  '- [ ] 3 · Verify: github-mechanics, ado-mechanics scoped to what changed' "$(grep '^- \[ \] 3 · ' "$rf")"
check "init lists each named verification as pending, between the checklist and the plan" \
  '## Verification results

- github-mechanics: pending
- ado-mechanics: pending

## Design and plan' \
  "$(sed -n '/^## Verification results$/,/^## Design and plan$/p' "$rf")"
check "the results section follows the checklist" \
  '- [ ] 9' "$(grep -B2 '^## Verification results$' "$rf" | head -1 | cut -c1-7)"
check "no verification named, no results section" 0 \
  "$(at "$repo" init 21 | jq -r .run_file | xargs grep -c '^## Verification results$')"
check "None. names nothing" 0 \
  "$(at "$repo" init 22 --verifications 'None.' | jq -r .run_file | xargs grep -c '^## Verification results$')"
check "free text is not a name list" 0 \
  "$(at "$repo" init 23 --verifications 'the usual checks, as listed' | jq -r .run_file | xargs grep -c '^## Verification results$')"

at "$repo" close 0 --file "$rf" >/dev/null
for p in 1 2; do at "$repo" open "$p" --file "$rf" >/dev/null; at "$repo" close "$p" --file "$rf" >/dev/null; done
at "$repo" open 3 --file "$rf" >/dev/null
before=$(cat "$rf")
check "close 3 refuses while a verification is pending, naming both" \
  'phase 3 cannot close with verifications pending: github-mechanics, ado-mechanics; record each with `run-file close 3 --result <name>=<pass|fail|deferred-to-ci|unavailable|unexercised|n/a>`' \
  "$(inerr "$repo" close 3 --file "$rf")"
check_rc "the pending refusal exits 1" 1 "$(inrc "$repo" close 3 --file "$rf")"
check "the refused close left the phase open" 1 "$(grep -c '^- \[ \] 3 · .* in_progress ([0-9][0-9]:[0-9][0-9]→)$' "$rf")"
check "the refused close changed nothing" "$before" "$(cat "$rf")"

check "a refused close still records the result it was given" \
  'phase 3 cannot close with verifications pending: ado-mechanics; record each with `run-file close 3 --result <name>=<pass|fail|deferred-to-ci|unavailable|unexercised|n/a>`' \
  "$(inerr "$repo" close 3 --file "$rf" --result github-mechanics=pass)"
check "the recorded result is in the section" '- github-mechanics: pass' "$(grep '^- github-mechanics: ' "$rf")"
check "the other stays pending" '- ado-mechanics: pending' "$(grep '^- ado-mechanics: ' "$rf")"
c=$(at "$repo" close 3 --file "$rf" --result 'ado-mechanics=n/a: Applies when was false'); crc=$?
check_rc "close 3 exits ok once every name has a result" 0 "$crc"
check "close 3 answers once every name has a result" completed "$(jq -r .mirror <<<"$c")"
check "a result may carry a note" '- ado-mechanics: n/a: Applies when was false' "$(grep '^- ado-mechanics: ' "$rf")"
check "phase 3 is closed" 1 "$(grep -c '^- \[x\] 3 · .*([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9])$' "$rf")"

# A word outside the set, or a name init never saw, is malformed and writes nothing.
rg=$(at "$repo" init 24 --verifications 'github-mechanics' | jq -r .run_file)
at "$repo" close 0 --file "$rg" >/dev/null
for p in 1 2; do at "$repo" open "$p" --file "$rg" >/dev/null; at "$repo" close "$p" --file "$rg" >/dev/null; done
at "$repo" open 3 --file "$rg" >/dev/null
was=$(cat "$rg")
check_rc "a result word outside the set is malformed" 2 "$(inrc "$repo" close 3 --file "$rg" --result github-mechanics=maybe)"
check_rc "a result for a name init never saw is malformed" 2 "$(inrc "$repo" close 3 --file "$rg" --result nope=pass)"
check_rc "a result with no word is malformed" 2 "$(inrc "$repo" close 3 --file "$rg" --result github-mechanics)"
check_rc "--result on another phase is malformed" 2 "$(inrc "$repo" close 4 --file "$rg" --result github-mechanics=pass)"
check "the refused results changed nothing" "$was" "$(cat "$rg")"
for w in pass fail deferred-to-ci unavailable unexercised n/a; do
  at "$repo" close 3 --file "$rg" --result "github-mechanics=$w" >/dev/null 2>&1
  check "the word $w is recorded" "- github-mechanics: $w" "$(grep '^- github-mechanics: ' "$rg")"
  at "$repo" open 3 --file "$rg" >/dev/null 2>&1
done

# No verification named: close 3 needs no result, and --result has no name to take.
rn=$(at "$repo" init 25 | jq -r .run_file)
at "$repo" close 0 --file "$rn" >/dev/null
for p in 1 2; do at "$repo" open "$p" --file "$rn" >/dev/null; at "$repo" close "$p" --file "$rn" >/dev/null; done
at "$repo" open 3 --file "$rn" >/dev/null
check_rc "close 3 with nothing named needs no result" 0 "$(inrc "$repo" close 3 --file "$rn")"
check_rc "--result with nothing named is malformed" 2 "$(inrc "$repo" close 3 --file "$rn" --result a=pass)"

# next closes through the same check: it cannot step past a pending verification.
rx=$(at "$repo" init 26 --verifications 'github-mechanics' | jq -r .run_file)
at "$repo" close 0 --file "$rx" >/dev/null
for p in 1 2; do at "$repo" open "$p" --file "$rx" >/dev/null; at "$repo" close "$p" --file "$rx" >/dev/null; done
at "$repo" open 3 --file "$rx" >/dev/null
was=$(cat "$rx")
check "next from phase 3 refuses while a verification is pending" \
  'phase 3 cannot close with verifications pending: github-mechanics; record each with `run-file close 3 --result <name>=<pass|fail|deferred-to-ci|unavailable|unexercised|n/a>`' \
  "$(inerr "$repo" next 4 --file "$rx")"
check "the refused next wrote nothing" "$was" "$(cat "$rx")"

# --- init from the ship profile -------------------------------------------------

rp=$(at "$repo" init 30 --from-profile "$profile")
fp=$(jq -r .run_file <<<"$rp")
check "the tripwires slot is the profile's value" \
  '- [ ] 2 · Implement: classify (docs/code/infra), lane keys, TDD per class, tripwires no raw SQL; no new dependency' "$(grep '^- \[ \] 2 · ' "$fp")"
check "the verification slot is the headings under ## Verification" \
  '- [ ] 3 · Verify: github-mechanics, ado-mechanics scoped to what changed' "$(grep '^- \[ \] 3 · ' "$fp")"
check "the reviewers slot is the headings under ## Reviewers" \
  '- [ ] 7 · Reviewers: copilot, claude, one bounded pass each' "$(grep '^- \[ \] 7 · ' "$fp")"
check "the legs slot is the leg names" \
  '- [ ] 8 · CI: resolve any conflict, land bump-guard, lint green' "$(grep '^- \[ \] 8 · ' "$fp")"
check "a profile's verifications get their results section" \
  '- github-mechanics: pending
- ado-mechanics: pending' "$(grep '^- [a-z-]*: pending$' "$fp")"
check "a heading outside ## Verification is not a verification" 0 "$(grep -c 'not-a-verification' "$fp")"
check "the JSON still returns the items" 10 "$(jq '.items | length' <<<"$rp")"

ro=$(at "$repo" init 31 --from-profile "$profile" --legs 'my-leg' --tripwires 'explicit' | jq -r .run_file)
check "an explicit --legs wins over the profile" '- [ ] 8 · CI: resolve any conflict, land my-leg green' "$(grep '^- \[ \] 8 · ' "$ro")"
check "an explicit --tripwires wins over the profile" \
  '- [ ] 2 · Implement: classify (docs/code/infra), lane keys, TDD per class, tripwires explicit' "$(grep '^- \[ \] 2 · ' "$ro")"
check "the slots not given explicitly still come from the profile" \
  '- [ ] 7 · Reviewers: copilot, claude, one bounded pass each' "$(grep '^- \[ \] 7 · ' "$ro")"

# The path left out is the current checkout's own profile.
mkdir -p "$wt/docs/agents"; cp "$profile" "$wt/docs/agents/ship.md"
check "--from-profile with no path reads the checkout's profile" \
  '- [ ] 3 · Verify: github-mechanics, ado-mechanics scoped to what changed' \
  "$(at "$wt" init 32 --from-profile | jq -r .run_file | xargs grep '^- \[ \] 3 · ')"
check "a flag after a bare --from-profile is not its path" \
  '- [ ] 8 · CI: resolve any conflict, land bump-guard, lint green' \
  "$(at "$wt" init 33 --from-profile --rebuild | jq -r .run_file | xargs grep '^- \[ \] 8 · ')"
check_rc "a profile that is not there is malformed" 2 "$(inrc "$repo" init 34 --from-profile "$tmp/nope.md")"
check_rc "no path outside a checkout is malformed" 2 "$(GIT_CEILING_DIRECTORIES=$tmp inrc "$nogit" init 35 --scratchpad "$tmp/sp" --from-profile)"

# A profile with no Legs line, no verification, no reviewer: the defaults stand.
printf '## Local gate\n\nTripwires: None.\n' > "$tmp/bare.md"
fb=$(at "$repo" init 36 --from-profile "$tmp/bare.md" | jq -r .run_file)
check "an empty profile leaves legs None." '- [ ] 8 · CI: resolve any conflict, land None. green' "$(grep '^- \[ \] 8 · ' "$fb")"
check "an empty profile leaves verifications unnamed" 0 "$(grep -c '^## Verification results$' "$fb")"

# Every heading under ## Verification is a name, whatever it holds: a name with a
# space still gets its results section, and close 3 still refuses while it has
# no result. A hand-passed list keeps the stricter name-shaped rule.
rsp=$(at "$repo" init 37 --from-profile "$spaced")
fs=$(jq -r .run_file <<<"$rsp")
check "a profile heading with a space is a verification name" \
  '- Docs check: pending
- Build: unit tests: pending
- github-mechanics: pending' "$(grep '^- .*: pending$' "$fs")"
check "the checklist line still joins the headings" \
  '- [ ] 3 · Verify: Docs check, Build: unit tests, github-mechanics scoped to what changed' "$(grep '^- \[.\] 3 · ' "$fs")"
at "$repo" close 0 --file "$fs" >/dev/null
for p in 1 2; do at "$repo" open "$p" --file "$fs" >/dev/null; at "$repo" close "$p" --file "$fs" >/dev/null; done
at "$repo" open 3 --file "$fs" >/dev/null
check "close 3 refuses while the spaced name has no result" \
  'phase 3 cannot close with verifications pending: Docs check, Build: unit tests, github-mechanics; record each with `run-file close 3 --result <name>=<pass|fail|deferred-to-ci|unavailable|unexercised|n/a>`' \
  "$(inerr "$repo" close 3 --file "$fs")"
# A name holding a colon is still pending: it is found by its prefix, as --result finds it.
check "close 3 refuses while only the colon-bearing name has no result" \
  'phase 3 cannot close with verifications pending: Build: unit tests; record each with `run-file close 3 --result <name>=<pass|fail|deferred-to-ci|unavailable|unexercised|n/a>`' \
  "$(inerr "$repo" close 3 --file "$fs" --result 'Docs check=n/a: no doc touched' --result 'github-mechanics=pass: waiting: pending')"
at "$repo" close 3 --file "$fs" --result 'Build: unit tests=pass' >/dev/null
check "a result names the spaced name and splits on the first =" \
  '- Docs check: n/a: no doc touched' "$(grep '^- Docs check: ' "$fs")"
check "close 3 passes once the spaced name has its result" 1 \
  "$(grep -c '^- \[x\] 3 · .*([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9])$' "$fs")"
check "a hand-passed spaced name list has no results section" 0 \
  "$(at "$repo" init 38 --verifications 'Docs check, github-mechanics' | jq -r .run_file | xargs grep -c '^## Verification results$')"
# A name carrying `=` could never be addressed by --result, so init refuses it.
printf '## Verification\n\n### a=b\n\nText.\n' > "$tmp/eq.md"
check_rc "a profile heading carrying = is malformed" 2 "$(inrc "$repo" init 39 --from-profile "$tmp/eq.md")"

# --- the gate record ------------------------------------------------------------

fg=$(at "$repo" init 40 | jq -r .run_file)
rec=$(printf '{"verdict":"pass","base":"origin/main","lane":"full","gates":{}}' | at "$repo" gate record - --file "$fg")
check "gate record answers the head and the verdict" "$first pass" "$(jq -r '[.head, .verdict] | join(" ")' <<<"$rec")"
check "gate record names the run file" "$fg" "$(jq -r .run_file <<<"$rec")"
check "the record is a line in a section at the end" \
  "## Local gate" "$(tail -3 "$fg" | grep '^## ')"
check "the line is clock, full sha, verdict, gates" 1 "$(grep -cE "^- [0-9]{2}:[0-9]{2} $first pass \{\}$" "$fg")"

printf '{"verdict":"fail"}' > "$tmp/gate.json"
at "$repo" gate record "$tmp/gate.json" --file "$fg" --head 1111111111111111111111111111111111111111 >/dev/null
check "a second record appends to the same section" 1 "$(grep -c '^## Local gate$' "$fg")"
check "an explicit --head is recorded, a verdict with no gates carries none" 1 "$(grep -cE '^- [0-9]{2}:[0-9]{2} 1{40} fail$' "$fg")"

# A section the run wrote below the gate record does not take the next line.
printf '\n## Notes\n\nby hand\n' >> "$fg"
at "$repo" gate record "$tmp/gate.json" --file "$fg" --head 2222222222222222222222222222222222222222 >/dev/null
check "a record inserts into its own section, not at the end of the file" \
  1 "$(awk '/^## Local gate$/{f=1;next} /^## /{f=0} f && /2{40} fail$/' "$fg" | wc -l | tr -d ' ')"

check_rc "unparseable gate JSON is malformed" 2 "$(printf 'not json' | inrc "$repo" gate record - --file "$fg")"
check_rc "gate JSON with no verdict is malformed" 2 "$(printf '{"base":"x"}' | inrc "$repo" gate record - --file "$fg")"
check_rc "a gate file that is not there is malformed" 2 "$(inrc "$repo" gate record "$tmp/nope.json" --file "$fg")"
check_rc "a verdict with a space in it is malformed" 2 "$(printf '{"verdict":"not ok"}' | inrc "$repo" gate record - --file "$fg")"

# gate read: the last record, and where the head stands against it.
fr=$(at "$repo" init 41 | jq -r .run_file)
check_rc "gate read with nothing recorded exits 1" 1 "$(inrc "$repo" gate read --head "$first" --file "$fr")"
check "gate read with nothing recorded says so" "no gate record in $fr" "$(inerr "$repo" gate read --head "$first" --file "$fr")"
printf '{"verdict":"pass"}' | at "$repo" gate record - --file "$fr" >/dev/null
g commit -q --allow-empty -m two
second=$(g rev-parse HEAD)
r=$(at "$repo" gate read --head "$first" --file "$fr")
check "the recorded head is current" "pass $first true 0" "$(jq -r '[.verdict, .head, .current, .behind] | join(" ")' <<<"$r")"
r=$(at "$repo" gate read --head "$second" --file "$fr")
check "a later head is not current, and counts the commits behind" "false 1" "$(jq -r '[.current, .behind] | join(" ")' <<<"$r")"
check "a short sha matches by prefix" true "$(at "$repo" gate read --head "${first:0:8}" --file "$fr" | jq -r .current)"
check "the recorded sha may be the short one" true \
  "$(printf '{"verdict":"pass"}' | at "$repo" gate record - --file "$fr" --head "${second:0:9}" >/dev/null; at "$repo" gate read --head "$second" --file "$fr" | jq -r .current)"
# One heading comparison: `gate record` finds `## Local gate` past trailing
# blanks, so `gate read` does too, rather than reading none from a heading the
# record was written under.
fh=$(at "$repo" init 4242 | jq -r .run_file)
printf '{"verdict":"fail"}' | at "$repo" gate record - --file "$fh" --head "$second" >/dev/null
sed -i 's/^## Local gate$/## Local gate  /' "$fh"
printf '{"verdict":"pass"}' | at "$repo" gate record - --file "$fh" --head "$second" >/dev/null
check "gate read finds the last record under a heading with trailing blanks" "pass" "$(at "$repo" gate read --head "$second" --file "$fh" | jq -r .verdict)"
sed -i 's/^## Local gate  $/## Local gates/' "$fh"
check_rc "a heading that only starts with Local gate is not the section" 1 "$(inrc "$repo" gate read --head "$second" --file "$fh")"
check "a head git cannot answer for is null behind" null \
  "$(at "$repo" gate read --head deadbeefdeadbeef --file "$fr" | jq -r .behind)"
check "gate read takes the last of several records" "pass" \
  "$(printf '{"verdict":"fail"}' | at "$repo" gate record - --file "$fr" --head "$first" >/dev/null
     printf '{"verdict":"pass"}' | at "$repo" gate record - --file "$fr" --head "$first" >/dev/null
     at "$repo" gate read --head "$first" --file "$fr" | jq -r .verdict)"
# The gates object rides on the line, so the merge gate can cite it on its Local
# gate row without re-running the gate.
fq=$(at "$repo" init 42 | jq -r .run_file)
printf '{"verdict":"pass","gates":{"lint":"pass","tests":"pass: 12 cases","note":"a b"}}' | at "$repo" gate record - --file "$fq" >/dev/null
check "the line carries the gates as compact JSON" 1 \
  "$(grep -cF -- "$second pass {\"lint\":\"pass\",\"tests\":\"pass: 12 cases\",\"note\":\"a b\"}" "$fq")"
check "gate read returns the gates, spaces inside a value intact" \
  '{"lint":"pass","tests":"pass: 12 cases","note":"a b"}' "$(at "$repo" gate read --head "$second" --file "$fq" | jq -c .gates)"
check "gate read still returns the verdict and head beside the gates" "pass $second" \
  "$(at "$repo" gate read --head "$second" --file "$fq" | jq -r '[.verdict, .head] | join(" ")')"
printf '{"verdict":"pass"}' | at "$repo" gate record - --file "$fq" --head "$first" >/dev/null
check "a verdict recorded with no gates reads null" null "$(at "$repo" gate read --head "$first" --file "$fq" | jq -c .gates)"
printf '{"verdict":"pass","gates":"all"}' | at "$repo" gate record - --file "$fq" --head "$first" >/dev/null
check "a gates value that is not an object is no gates" null "$(at "$repo" gate read --head "$first" --file "$fq" | jq -c .gates)"
# A record from before the gates were stored is the old three-field line.
fo=$(at "$repo" init 43 | jq -r .run_file)
printf '\n## Local gate\n\n- 10:00 %s pass\n' "$first" >> "$fo"
check "an old three-field line reads null gates" "pass null" \
  "$(at "$repo" gate read --head "$first" --file "$fo" | jq -r '[.verdict, (.gates | tostring)] | join(" ")')"
printf '\n- 10:05 %s pass {not json\n' "$first" >> "$fo"
check_rc "a gates field that is not JSON is a refusal, not a verdict" 1 "$(inrc "$repo" gate read --head "$first" --file "$fo")"

# One sha pattern for both: 7 to 64 hex digits.
check_rc "gate read takes a 7-digit head" 0 "$(inrc "$repo" gate read --head "${first:0:7}" --file "$fr")"
check_rc "gate read refuses a 6-digit head" 2 "$(inrc "$repo" gate read --head "${first:0:6}" --file "$fr")"
check_rc "gate read refuses a 65-digit head" 2 "$(inrc "$repo" gate read --head "${first}00000000000000000000000000" --file "$fr")"
check_rc "gate record takes a 7-digit head" 0 "$(printf '{"verdict":"pass"}' | inrc "$repo" gate record - --file "$fr" --head "${first:0:7}")"
check_rc "gate record refuses a 6-digit head" 2 "$(printf '{"verdict":"pass"}' | inrc "$repo" gate record - --file "$fr" --head "${first:0:6}")"
check_rc "gate read needs --head" 2 "$(inrc "$repo" gate read --file "$fr")"
check_rc "gate with no subcommand is malformed" 2 "$(inrc "$repo" gate)"

finish
