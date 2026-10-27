#!/usr/bin/env bash
# Split by behaviour from tests/run-file-record.test.sh: init from the ship profile and skip 3 cases.
# The run-file mechanic's record: where it lives, what init takes from the ship
# profile, the Phase 3 results and the gate record. Driven end to end over a
# fixture repo with a worktree, so the record root's key is derived from the real
# `git rev-parse --git-common-dir` and not a stand-in, under a throwaway
# XDG_STATE_HOME; the mechanic reaches no host. The flips
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
g worktree add -q "$wt" -b feat/x-7
export XDG_STATE_HOME=$tmp/state

# at <dir> <args...>: the mechanic run from a directory, stdout only.
at()    { local d=$1; shift; ( cd "$d" && bash "$m" "$@" 2>/dev/null ); }
inrc()  { local d=$1; shift; ( cd "$d" && bash "$m" "$@" >/dev/null 2>&1 ); echo $?; }
inerr() { local d=$1; shift; ( cd "$d" && bash "$m" "$@" 2>/dev/null ) | jq -r '.error'; }
# A result carries the head close 3 recorded it on; the cases about its word and
# note read it without that stamp, which the stamp cases below assert.
unstamp() { sed -E 's/ at [0-9a-f]{40}(: |$)/\1/'; }
entry() { grep "$1" "$2" | unstamp; }

# --- init from the ship profile -------------------------------------------------

rp=$(at "$repo" init 30 --from-profile "$profile")
fp=$(jq -r .run_file <<<"$rp")
root=$(dirname "$(jq -r .scratch <<<"$rp")")
nogit=$tmp/nogit; mkdir -p "$nogit"
check "the tripwires slot is the profile's value" \
  '- [ ] 2 · Implement: classify (docs/code/infra), lane keys, TDD per class, tripwires no raw SQL; no new dependency' "$(entry '^- \[ \] 2 · ' "$fp")"
check "the verification slot is the headings under ## Verification" \
  '- [ ] 3 · Verify: github-mechanics, ado-mechanics scoped to what changed' "$(entry '^- \[ \] 3 · ' "$fp")"
check "the reviewers slot is the headings under ## Reviewers" \
  '- [ ] 7 · Reviewers: copilot, claude, one bounded pass each' "$(entry '^- \[ \] 7 · ' "$fp")"
check "the legs slot is the leg names" \
  '- [ ] 8 · CI: resolve any conflict, land bump-guard, lint green' "$(entry '^- \[ \] 8 · ' "$fp")"
check "a profile's verifications get their results section" \
  '- github-mechanics: pending
- ado-mechanics: pending' "$(entry '^- [a-z-]*: pending$' "$fp")"
check "a heading outside ## Verification is not a verification" 0 "$(grep -c 'not-a-verification' "$fp")"
check "the JSON still returns the items" 10 "$(jq '.items | length' <<<"$rp")"

ro=$(at "$repo" init 31 --from-profile "$profile" --legs 'my-leg' --tripwires 'explicit' | jq -r .run_file)
check "an explicit --legs wins over the profile" '- [ ] 8 · CI: resolve any conflict, land my-leg green' "$(entry '^- \[ \] 8 · ' "$ro")"
check "an explicit --tripwires wins over the profile" \
  '- [ ] 2 · Implement: classify (docs/code/infra), lane keys, TDD per class, tripwires explicit' "$(entry '^- \[ \] 2 · ' "$ro")"
check "the slots not given explicitly still come from the profile" \
  '- [ ] 7 · Reviewers: copilot, claude, one bounded pass each' "$(entry '^- \[ \] 7 · ' "$ro")"

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
check "an empty profile leaves legs None." '- [ ] 8 · CI: resolve any conflict, land None. green' "$(entry '^- \[ \] 8 · ' "$fb")"
check "an empty profile leaves verifications unnamed" 0 "$(grep -c '^## Verification results$' "$fb")"

# Every heading under ## Verification is a name, whatever it holds: a name with a
# space still gets its results section, and close 3 still refuses while it has
# no result. A hand-passed list keeps the stricter name-shaped rule.
rsp=$(at "$repo" init 37 --from-profile "$spaced")
fs=$(jq -r .run_file <<<"$rsp")
check "a profile heading with a space is a verification name" \
  '- Docs check: pending
- Build: unit tests: pending
- github-mechanics: pending' "$(entry '^- .*: pending$' "$fs")"
check "the checklist line still joins the headings" \
  '- [ ] 3 · Verify: Docs check, Build: unit tests, github-mechanics scoped to what changed' "$(entry '^- \[.\] 3 · ' "$fs")"
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
  '- Docs check: n/a: no doc touched' "$(entry '^- Docs check: ' "$fs")"
check "close 3 passes once the spaced name has its result" 1 \
  "$(grep -c '^- \[x\] 3 · .*([0-9][0-9]:[0-9][0-9]→[0-9][0-9]:[0-9][0-9])$' "$fs")"
check "a hand-passed spaced name list has no results section" 0 \
  "$(at "$repo" init 38 --verifications 'Docs check, github-mechanics' | jq -r .run_file | xargs grep -c '^## Verification results$')"
# A name carrying `=` could never be addressed by --result, so init refuses it.
printf '## Verification\n\n### a=b\n\nText.\n' > "$tmp/eq.md"
check_rc "a profile heading carrying = is malformed" 2 "$(inrc "$repo" init 39 --from-profile "$tmp/eq.md")"
# A name with a result word as a later field writes an entry
# the pending test reads as settled (`- Build: pass: pending` is name `Build`,
# result `pass`), so init refuses it, names it, and writes nothing.
printf '## Verification\n\n### lint\n\n### Build: pass\n' > "$tmp/word.md"
check_rc "a profile heading with a result word as a later field is malformed" 2 "$(inrc "$repo" init 71 --from-profile "$tmp/word.md")"
check "the refusal names the heading and says why" \
  "a Verification heading cannot carry a result word as a later field: 'Build: pass' would read as a settled result while pending; rename it" \
  "$(inerr "$repo" init 71 --from-profile "$tmp/word.md")"
check "the refused init wrote no Run file" no "$([ -e "$root/ship-71" ] && echo yes || echo no)"
for w in pass fail deferred-to-ci unavailable unexercised n/a; do
  printf '## Verification\n\n### x: %s\n' "$w" > "$tmp/word.md"
  check_rc "a heading ending in the field '$w' is malformed" 2 "$(inrc "$repo" init 72 --from-profile "$tmp/word.md")"
  printf '## Verification\n\n### x: %s: y\n' "$w" > "$tmp/word.md"
  check_rc "a heading with the field '$w' before another is malformed" 2 "$(inrc "$repo" init 72 --from-profile "$tmp/word.md")"
done
check "the refused inits wrote no Run file" no "$([ -e "$root/ship-72" ] && echo yes || echo no)"
# A rebuild goes through the same check, and a refused one leaves the record it
# was asked to replace as it was.
rb=$(at "$repo" init 73 --verifications lint | jq -r .run_file)
before=$(cat "$rb")
printf '## Verification\n\n### Build: pass\n' > "$tmp/word.md"
check_rc "a rebuild from such a profile is malformed" 2 "$(inrc "$repo" init 73 --rebuild --from-profile "$tmp/word.md")"
check "the refused rebuild left the Run file byte-for-byte" "$before" "$(cat "$rb")"
# A result word that is the whole name, part of a longer field or quoted, a
# name with no result word, and a result-word heading under another section
# all leave the entry unambiguous.
printf '## Verification\n\n### Lint: fail-fast\n\n### pass\n\n### Smoke: unavailable offline\n\n### Gate: '"'pass'"'\n\n### live check: punctuation\n\n## Reviewers\n\n### Build: pass\n' > "$tmp/ok.md"
ok=$(at "$repo" init 74 --from-profile "$tmp/ok.md" | jq -r .run_file)
check "names whose result words are not a later field are accepted" \
  "- Lint: fail-fast: pending
- pass: pending
- Smoke: unavailable offline: pending
- Gate: 'pass': pending
- live check: punctuation: pending" "$(sed -n '/^## Verification results$/,/^## Design and plan$/p' "$ok" | grep '^- ')"
# A result whose note ends `pending` is settled: close 3 passes over it.
printf '## Verification\n\n### github-mechanics\n' > "$tmp/one.md"
st=$(at "$repo" init 75 --from-profile "$tmp/one.md" | jq -r .run_file)
sed 's/^- github-mechanics: pending$/- github-mechanics: pass: waiting: pending/' "$st" > "$st.new" && mv "$st.new" "$st"
at "$repo" close 0 --file "$st" >/dev/null
for p in 1 2 3; do at "$repo" open "$p" --file "$st" >/dev/null; [ "$p" = 3 ] || at "$repo" close "$p" --file "$st" >/dev/null; done
check_rc "close 3 passes over a result whose note ends pending" 0 "$(inrc "$repo" close 3 --file "$st")"

# --- skip 3 settles the results -------------------------------------------------

# A skipped phase 3 has no close to take a --result, so the skip settles every
# result still pending as n/a with its reason, matched by the full name.
sk=$(at "$repo" init 61 --from-profile "$spaced" | jq -r .run_file)
at "$repo" close 0 --file "$sk" >/dev/null
for p in 1 2; do at "$repo" open "$p" --file "$sk" >/dev/null; at "$repo" close "$p" --file "$sk" >/dev/null; done
sed 's/^- github-mechanics: pending$/- github-mechanics: pass: waiting: pending/' "$sk" > "$sk.new" && mv "$sk.new" "$sk"
at "$repo" skip 6 'small lane' --file "$sk" >/dev/null
check "skip of another phase leaves pending results pending" \
  '- Docs check: pending
- Build: unit tests: pending' "$(entry '^- .*: pending$' "$sk" | grep -v '^- github-mechanics: ')"
at "$repo" open 3 --file "$sk" >/dev/null
before=$(cat "$sk")
check_rc "skip 3 over an open phase 3 is refused" 1 "$(inrc "$repo" skip 3 'docs class' --file "$sk")"
check "the refusal names the open phase" \
  "phase 3 is open, so it cannot be skipped: close it with \`close 3 --result <name>=n/a\` per pending Verification" "$(inerr "$repo" skip 3 'docs class' --file "$sk")"
check "the refused skip left the Run file byte-for-byte" "$before" "$(cat "$sk")"
sk2=$(at "$repo" init 62 --from-profile "$spaced" | jq -r .run_file)
before=$(cat "$sk2")
check_rc "a multi-line skip 3 reason is malformed" 2 "$(inrc "$repo" skip 3 "$(printf 'docs class\nsecond line')" --file "$sk2")"
check "the refusal names the newline" \
  'a phase is one line: that reason carries a newline; reword it' \
  "$(inerr "$repo" skip 3 "$(printf 'docs class\nsecond line')" --file "$sk2")"
check "the refused multi-line reason left the Run file byte-for-byte" "$before" "$(cat "$sk2")"
sj=$(at "$repo" skip 3 'docs class: no verification applies' --file "$sk2")
check "skip 3 keeps its JSON shape" 'mirror,phase,reason,run_file,state' "$(jq -r 'del(.line) | keys | join(",")' <<<"$sj")"
check "skip 3 settles each pending result as n/a with its reason, by its full name" \
  '- Docs check: n/a: docs class: no verification applies
- Build: unit tests: n/a: docs class: no verification applies
- github-mechanics: n/a: docs class: no verification applies' \
  "$(sed -n '/^## Verification results$/,/^## Design and plan$/p' "$sk2" | grep '^- ')"
at "$repo" skip 3 'small lane' --file "$sk2" >/dev/null
check "a second skip 3 re-stamps the phase but keeps the settled results" \
  '- [x] 3 · Verify: Docs check, Build: unit tests, github-mechanics scoped to what changed skipped (small lane)
- Docs check: n/a: docs class: no verification applies' \
  "$(grep -e '^- \[x\] 3 · ' -e '^- Docs check: ' "$sk2")"
sk3=$(at "$repo" init 63 --from-profile "$spaced" | jq -r .run_file)
sed 's/^- github-mechanics: pending$/- github-mechanics: pass: waiting: pending/' "$sk3" > "$sk3.new" && mv "$sk3.new" "$sk3"
at "$repo" skip 3 'docs class' --file "$sk3" >/dev/null
check "a result already carrying a word keeps it" \
  '- github-mechanics: pass: waiting: pending' "$(entry '^- github-mechanics: ' "$sk3")"
check "the pending ones beside it are settled" \
  '- Docs check: n/a: docs class
- Build: unit tests: n/a: docs class' "$(grep -e '^- Docs check: ' -e '^- Build: unit tests: ' "$sk3")"
# Only the results section is settled, and each entry by its whole line: a name
# that begins another settles only its own, and a decoy elsewhere stays.
printf '## Verification\n\n### lint\n\n### lint: strict\n' > "$tmp/prefix.md"
sk5=$(at "$repo" init 65 --from-profile "$tmp/prefix.md" | jq -r .run_file)
sed 's/^- lint: strict: pending$/- lint: strict: pass/' "$sk5" > "$sk5.new" && mv "$sk5.new" "$sk5"
printf -- '- lint: pending\n' >> "$sk5"
at "$repo" skip 3 'docs class' --file "$sk5" >/dev/null
check "a name that begins another settles only its own entry" \
  '- lint: n/a: docs class
- lint: strict: pass' "$(sed -n '/^## Verification results$/,/^## Design and plan$/p' "$sk5" | grep '^- ')"
check "a pending line outside the results section is left as it is" '- lint: pending' "$(tail -1 "$sk5")"
# A rebuilt Run file carries a skipped phase 3 with its results pending; a
# second skip re-stamps it and settles them.
sk6=$(at "$repo" init 66 --from-profile "$spaced" --state '3=skipped:small lane' | jq -r .run_file)
at "$repo" skip 3 'small lane' --file "$sk6" >/dev/null
check "a re-skip settles results a rebuilt skipped phase 3 left pending" 0 "$(grep -c ': pending$' "$sk6")"
sk4=$(at "$repo" init 64 | jq -r .run_file)
before=$(cat "$sk4")
at "$repo" skip 3 'docs class' --file "$sk4" >/dev/null
check "skip 3 with no verification named writes only the phase line" \
  "$(printf '%s\n' "$before" | grep -v '^- \[.\] 3 · ')" "$(grep -v '^- \[.\] 3 · ' "$sk4")"


finish
