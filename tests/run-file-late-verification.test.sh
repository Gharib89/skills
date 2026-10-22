#!/usr/bin/env bash
# Split by behaviour from tests/run-file-record.test.sh: a Verification added after init and results after phase 3 closed.
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

# --- a Verification the PR adds after init ----------------------------------------
# gate clean judges the checkout profile's `## Verification` headings, so close 3
# takes a result for a heading added there after init, appending its entry.
added=$tmp/added
git init -q -b main "$added"; mkdir -p "$added/docs/agents"; cp "$profile" "$added/docs/agents/ship.md"
git -C "$added" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m one
added_head=$(git -C "$added" rev-parse HEAD)
add_heading() { # add_heading <heading> [<section>]: a new first heading under ## Verification, or <section>
  awk -v h="$1" -v s="## ${2:-Verification}" '{ print } $0 == s { print ""; print "### " h }' "$added/docs/agents/ship.md" > "$tmp/added.md" \
    && mv "$tmp/added.md" "$added/docs/agents/ship.md"
}
to_phase3() { # to_phase3 <run file>
  at "$added" close 0 --file "$1" >/dev/null
  for p in 1 2; do at "$added" open "$p" --file "$1" >/dev/null; at "$added" close "$p" --file "$1" >/dev/null; done
  at "$added" open 3 --file "$1" >/dev/null
}
printf '{"status":"green","head_sha":"%s","checks":[],"legs":[],"missing_legs":[],"failing":[],"non_leg_failing":[],"unlisted":[],"waited_s":0}\n' "$added_head" > "$tmp/ci.json"
holds_verif() { # holds_verif <run file> <name>: the gate-clean holds naming that verification
  at "$added" gate clean "$tmp/ci.json" --head "$added_head" --file "$1" \
    | jq -r --arg v "verification $2:" 'if (.held_by | type) == "array"
        then [.held_by[] | select(startswith($v))] | join(",") else "no answer: \(.error)" end'
}
fa=$(at "$added" init 80 --from-profile | jq -r .run_file)
to_phase3 "$fa"
add_heading live-run
check "gate clean holds a heading the profile gained after init" 'verification live-run: missing; record it with `run-file close 3 --result live-run=<word>`' "$(holds_verif "$fa" live-run)"
was=$(cat "$fa")
check_rc "a name neither the Run file nor the profile names is malformed" 2 \
  "$(inrc "$added" close 3 --file "$fa" --result github-mechanics=pass --result ado-mechanics=pass --result nope=pass)"
check "the refusal says both were checked" \
  "--result names 'nope', which neither the Run file's Verification results nor the profile's Verification headings name" \
  "$(inerr "$added" close 3 --file "$fa" --result nope=pass)"
check "the refused name left the record unchanged" "$was" "$(cat "$fa")"
add_heading 'Build: pass'
check_rc "a profile-added heading with a result word as a later field is malformed" 2 \
  "$(inrc "$added" close 3 --file "$fa" --result 'Build: pass=n/a')"
check "that refusal is init's" \
  "a Verification heading cannot carry a result word as a later field: 'Build: pass' would read as a settled result while pending; rename it" \
  "$(inerr "$added" close 3 --file "$fa" --result 'Build: pass=n/a')"
# --result splits the name at its first `=`, so a heading carrying one is never
# the name looked up: its tail reaches the word check instead.
add_heading 'a=b'
check "a profile-added heading carrying = cannot be named: its tail is refused as the word" \
  "--result word 'b=pass' is not one of pass, fail, deferred-to-ci, unavailable, unexercised, n/a" \
  "$(inerr "$added" close 3 --file "$fa" --result 'a=b=pass')"
check_rc "that refusal is malformed" 2 "$(inrc "$added" close 3 --file "$fa" --result 'a=b=pass')"
check "the refused headings left the record unchanged" "$was" "$(cat "$fa")"
# The lookup is the whole heading under ## Verification and nowhere else.
cp "$profile" "$added/docs/agents/ship.md"; add_heading live-run
check "a prefix of an added heading is no name" \
  "--result names 'live', which neither the Run file's Verification results nor the profile's Verification headings name" \
  "$(inerr "$added" close 3 --file "$fa" --result live=pass)"
check_rc "the prefix refusal is malformed" 2 "$(inrc "$added" close 3 --file "$fa" --result live=pass)"
add_heading decoy Reviewers
check "a ### heading under another section is no name" \
  "--result names 'decoy', which neither the Run file's Verification results nor the profile's Verification headings name" \
  "$(inerr "$added" close 3 --file "$fa" --result decoy=pass)"
check_rc "the decoy refusal is malformed" 2 "$(inrc "$added" close 3 --file "$fa" --result decoy=pass)"
check "the near misses left the record unchanged" "$was" "$(cat "$fa")"
cp "$profile" "$added/docs/agents/ship.md"; add_heading 'live-run  '
check_rc "close 3 takes a result for the heading the profile gained, trailing blanks trimmed as gate clean trims them" 0 \
  "$(inrc "$added" close 3 --file "$fa" --result github-mechanics=pass --result ado-mechanics=pass --result live-run=n/a)"
check "the new entry is appended to the results section" \
  '## Verification results

- github-mechanics: pass
- ado-mechanics: pass
- live-run: n/a

## Design and plan' \
  "$(sed -n '/^## Verification results$/,/^## Design and plan$/p' "$fa" | unstamp)"
check "gate clean no longer holds the added heading" '' "$(holds_verif "$fa" live-run)"
add_heading second
at "$added" open 3 --file "$fa" >/dev/null
check_rc "a re-opened phase 3 takes a heading added after it closed" 0 "$(inrc "$added" close 3 --file "$fa" --result second=pass)"
check "that heading is recorded" '- second: pass' "$(entry '^- second: ' "$fa")"
# A profile that named no Verification at init has no results section to append to.
printf '## Local gate\n\nTripwires: None.\n\n## CI\n\nLegs: None.\n\n## Reviewers\n\nNone.\n\n## Verification\n' > "$added/docs/agents/ship.md"
fe=$(at "$added" init 81 --from-profile | jq -r .run_file)
to_phase3 "$fe"
add_heading first-check
check_rc "the first heading a PR adds is recorded" 0 "$(inrc "$added" close 3 --file "$fe" --result first-check=pass)"
check "it opens the results section" '## Verification results

- first-check: pass' "$(sed -n '/^## Verification results$/,$p' "$fe" | unstamp)"
check "gate clean reads the section it opened" '' "$(holds_verif "$fe" first-check)"
# An added heading that prefixes one init recorded finds no entry of its own.
printf '## Local gate\n\nTripwires: None.\n\n## CI\n\nLegs: None.\n\n## Reviewers\n\nNone.\n\n## Verification\n\n### lint: strict\n' > "$added/docs/agents/ship.md"
fp=$(at "$added" init 82 --from-profile | jq -r .run_file)
to_phase3 "$fp"
add_heading lint
check_rc "an added heading that prefixes a recorded one takes its own result" 0 \
  "$(inrc "$added" close 3 --file "$fp" --result lint=n/a --result 'lint: strict=pass')"
check "each result lands on its own entry" '## Verification results

- lint: strict: pass
- lint: n/a

## Design and plan' "$(sed -n '/^## Verification results$/,/^## Design and plan$/p' "$fp" | unstamp)"
check "gate clean holds neither" '' "$(holds_verif "$fp" lint)"
# The reverse: init recorded the shorter name, so the added longer entry lands
# after it, the last row gate clean's prefix would read for it.
printf '## Local gate\n\nTripwires: None.\n\n## CI\n\nLegs: None.\n\n## Reviewers\n\nNone.\n\n## Verification\n\n### lint\n' > "$added/docs/agents/ship.md"
fr=$(at "$added" init 83 --from-profile | jq -r .run_file)
to_phase3 "$fr"
add_heading 'lint: strict'
check_rc "a recorded name that prefixes an added heading takes its own result" 0 \
  "$(inrc "$added" close 3 --file "$fr" --result lint=pass --result 'lint: strict=pass')"
check "gate clean reads each entry as its own" '' "$(holds_verif "$fr" lint)"

# --- a result recorded after phase 3 closed -----------------------------------------
# A heading a phase-4 or phase-7 fix adds owes a result after phase 3 has closed
# or been skipped, so close 3 records it there and leaves the row as is.
row3() { grep '^- \[.\] 3 · ' "$1"; }
cp "$profile" "$added/docs/agents/ship.md"
fl=$(at "$added" init 84 --from-profile | jq -r .run_file)
to_phase3 "$fl"
at "$added" close 3 --file "$fl" --result github-mechanics=pass --result ado-mechanics=pass >/dev/null
at "$added" open 4 --file "$fl" >/dev/null
add_heading late-check
row=$(row3 "$fl")
r=$(at "$added" close 3 --file "$fl" --result late-check=pass)
check "close 3 on a closed phase answers recorded, with no mirror" 'recorded false' "$(jq -r '"\(.state) \(has("mirror"))"' <<<"$r")"
check "the late result is recorded" '- late-check: pass' "$(entry '^- late-check: ' "$fl")"
check "phase 3's row is unchanged" "$row" "$(row3 "$fl")"
check "phase 4 is still the open phase" yes "$(grep -q '^- \[ \] 4 · .* in_progress (' "$fl" && echo yes || echo no)"
check "gate clean no longer holds the late heading" '' "$(holds_verif "$fl" late-check)"
check_rc "a recorded name on a closed phase 3 takes a new result" 0 "$(inrc "$added" close 3 --file "$fl" --result github-mechanics=fail)"
check "it replaces the entry" '- github-mechanics: fail' "$(entry '^- github-mechanics: ' "$fl")"
check "a re-run recorded after phase 3 closed carries its head" "- github-mechanics: fail at $added_head" "$(grep '^- github-mechanics: ' "$fl")"
was=$(cat "$fl")
check "a name nothing names is refused on a closed phase 3" \
  "--result names 'nope', which neither the Run file's Verification results nor the profile's Verification headings name" \
  "$(inerr "$added" close 3 --file "$fl" --result late-check=fail --result nope=pass)"
check "a bad word is refused on a closed phase 3" \
  "--result word 'great' is not one of pass, fail, deferred-to-ci, unavailable, unexercised, n/a" \
  "$(inerr "$added" close 3 --file "$fl" --result late-check=great)"
check_rc "the bad-word refusal is malformed" 2 "$(inrc "$added" close 3 --file "$fl" --result late-check=great)"
check "the refusals left the record unchanged" "$was" "$(cat "$fl")"
check "close 3 with no result on a closed phase 3 is still refused" 'phase 3 is not open' "$(inerr "$added" close 3 --file "$fl")"
fn=$(at "$added" init 85 --from-profile | jq -r .run_file)
check "a result on a phase 3 never opened is still refused" \
  'phase 3 was never opened; run `run-file open 3` first, then close it' \
  "$(inerr "$added" close 3 --file "$fn" --result github-mechanics=pass)"
cp "$profile" "$added/docs/agents/ship.md"
fs=$(at "$added" init 86 --from-profile | jq -r .run_file)
at "$added" close 0 --file "$fs" >/dev/null
for p in 1 2; do at "$added" open "$p" --file "$fs" >/dev/null; at "$added" close "$p" --file "$fs" >/dev/null; done
at "$added" skip 3 'docs only' --file "$fs" >/dev/null
at "$added" open 4 --file "$fs" >/dev/null
add_heading late-check
row=$(row3 "$fs")
check_rc "a skipped phase 3 records a late result" 0 "$(inrc "$added" close 3 --file "$fs" --result late-check=pass)"
check "that result is recorded" '- late-check: pass' "$(entry '^- late-check: ' "$fs")"
check "the skipped row is unchanged" "$row" "$(row3 "$fs")"

finish
