#!/usr/bin/env bash
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
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

repo=$tmp/repo wt=$tmp/repo.worktrees/feat-7
git init -q -b main "$repo"
g() { git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
g commit -q --allow-empty -m one
first=$(g rev-parse HEAD)
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

# --- where the record lives -----------------------------------------------------

session=$tmp/session-scratchpad; mkdir -p "$session"
j=$(at "$wt" init 7)
root=$(dirname "$(jq -r .scratch <<<"$j")")
key=${root#"$XDG_STATE_HOME/ship/"}
check "init from a worktree writes under the state directory's ship root" "$XDG_STATE_HOME/ship" "$(dirname "$root")"
check "the repo key is one path component of digits below that root, so no git text" yes \
  "$([[ $key != "$root" && $key =~ ^[0-9]+$ ]] && echo yes || echo no)"
check "the run file sits under that root" "$root/ship-7/run.md" "$(jq -r .run_file <<<"$j")"
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

# Each clone keys its own root: two clones never share a record.
git clone -q "$repo" "$tmp/clone"
other=$(dirname "$(at "$tmp/clone" init 7 | jq -r .scratch)")
check "a second clone resolves its own root" yes "$([ "$other" != "$root" ] && [ "$(dirname "$other")" = "$XDG_STATE_HOME/ship" ] && echo yes || echo no)"
# With XDG_STATE_HOME unset, the root falls back to ~/.local/state.
check "no XDG_STATE_HOME falls back to ~/.local/state" "$tmp/home/.local/state/ship/${root##*/}/ship-7/run.md" \
  "$(env -u XDG_STATE_HOME HOME="$tmp/home" bash -c 'cd "$1" && bash "$2" init 7' _ "$wt" "$m" 2>/dev/null | jq -r .run_file)"
# A relative XDG_STATE_HOME is ignored, as the XDG spec requires: it would
# resolve under each worktree's own cwd.
check "a relative XDG_STATE_HOME falls back to ~/.local/state" "$tmp/home/.local/state/ship/${root##*/}/ship-8/run.md" \
  "$(XDG_STATE_HOME=state HOME="$tmp/home" bash -c 'cd "$1" && bash "$2" init 8' _ "$wt" "$m" 2>/dev/null | jq -r .run_file)"

# A cksum that fails would leave the key empty and every repo sharing one root,
# so init refuses rather than defaulting.
badck=$tmp/badck; mkdir -p "$badck"
printf '#!/bin/sh\nexit 1\n' > "$badck/cksum"; chmod +x "$badck/cksum"
check_rc "init with a failing cksum and no --scratchpad is malformed" 2 \
  "$(PATH=$badck:$PATH inrc "$wt" init 30)"
check "the refusal names cksum and --scratchpad" \
  "cksum failed: pass --scratchpad <dir>" "$(PATH=$badck:$PATH inerr "$wt" init 30)"
garbage=$tmp/garbage; mkdir -p "$garbage"
printf '#!/bin/sh\necho 12ab 5\n' > "$garbage/cksum"; chmod +x "$garbage/cksum"
check_rc "a cksum answering a non-digit key is refused too" 2 \
  "$(PATH=$garbage:$PATH inrc "$wt" init 31)"

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
  '- [ ] 3 · Verify: github-mechanics, ado-mechanics scoped to what changed' "$(entry '^- \[ \] 3 · ' "$rf")"
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
check "the recorded result is in the section" '- github-mechanics: pass' "$(entry '^- github-mechanics: ' "$rf")"
check "the other stays pending" '- ado-mechanics: pending' "$(entry '^- ado-mechanics: ' "$rf")"
c=$(at "$repo" close 3 --file "$rf" --result 'ado-mechanics=n/a: Applies when was false'); crc=$?
check_rc "close 3 exits ok once every name has a result" 0 "$crc"
check "close 3 answers once every name has a result" completed "$(jq -r .mirror <<<"$c")"
check "a result may carry a note" '- ado-mechanics: n/a: Applies when was false' "$(entry '^- ado-mechanics: ' "$rf")"
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
  check "the word $w is recorded" "- github-mechanics: $w" "$(entry '^- github-mechanics: ' "$rg")"
  at "$repo" open 3 --file "$rg" >/dev/null 2>&1
done

# Each result records the head it was proven on: the checkout's HEAD by default,
# or --head, which belongs to close 3 alone.
check "a result is stamped with the checkout's HEAD" "- ado-mechanics: n/a at $first: Applies when was false" "$(grep '^- ado-mechanics: ' "$rf")"
at "$repo" close 3 --file "$rg" --result github-mechanics=pass --head 0123abcd >/dev/null
check "--head names the stamp" '- github-mechanics: pass at 0123abcd' "$(grep '^- github-mechanics: ' "$rg")"
at "$repo" open 3 --file "$rg" >/dev/null
was=$(cat "$rg")
check_rc "a --head that is no sha is malformed" 2 "$(inrc "$repo" close 3 --file "$rg" --result github-mechanics=pass --head HEAD)"
check_rc "a --head that is no sha is malformed with no result too" 2 "$(inrc "$repo" close 3 --file "$rg" --head HEAD)"
check "the refusal says what --head takes" '--head takes a full or abbreviated commit sha' "$(inerr "$repo" close 3 --file "$rg" --head HEAD)"
check "--head on another phase is refused" '--head belongs to close 3' "$(inerr "$repo" close 4 --file "$rg" --head 0123abcd)"
check "the refused heads changed nothing" "$was" "$(cat "$rg")"

# A result written after the head moved names the head the verification ran at,
# when `ran` marked it (#933): the stamp the gate weighs is that head, not the
# one the record happened to be written on.
rh=$(at "$repo" init 27 --verifications 'github-mechanics, ado-mechanics' | jq -r .run_file)
at "$repo" close 0 --file "$rh" >/dev/null
for p in 1 2; do at "$repo" open "$p" --file "$rh" >/dev/null; at "$repo" close "$p" --file "$rh" >/dev/null; done
at "$repo" open 3 --file "$rh" >/dev/null
ranat=$(g rev-parse HEAD)
r=$(at "$repo" ran github-mechanics --file "$rh")
check "ran answers the head it marked" "{\"run_file\":\"$rh\",\"ran\":[{\"name\":\"github-mechanics\",\"head\":\"$ranat\"}]}" "$(jq -c . <<<"$r")"
check "ran writes one line under ## Evidence" "Ran: github-mechanics at $ranat" "$(sed -n '/^## Evidence$/,$p' "$rh" | grep '^Ran: ')"
g commit -q --allow-empty -m two
moved=$(g rev-parse HEAD)
at "$repo" close 3 --file "$rh" --result github-mechanics=pass --result ado-mechanics=n/a >/dev/null
check "the result carries the head the verification ran at, not the head recorded on" \
  "- github-mechanics: pass at $ranat" "$(grep '^- github-mechanics: ' "$rh")"
check "a result no ran marked is stamped with HEAD as before" \
  "- ado-mechanics: n/a at $moved" "$(grep '^- ado-mechanics: ' "$rh")"
at "$repo" open 3 --file "$rh" >/dev/null
at "$repo" ran github-mechanics --file "$rh" >/dev/null
check "a later ran for the same name replaces the earlier one" \
  "- github-mechanics: pass at $moved" "$(at "$repo" close 3 --file "$rh" --result github-mechanics=pass >/dev/null; grep '^- github-mechanics: ' "$rh")"
at "$repo" open 3 --file "$rh" >/dev/null
g commit -q --allow-empty -m three
at "$repo" close 3 --file "$rh" --result github-mechanics=pass --head 0123abcd >/dev/null
check "an explicit --head outranks a ran line" "- github-mechanics: pass at 0123abcd" "$(grep '^- github-mechanics: ' "$rh")"
at "$repo" open 3 --file "$rh" >/dev/null
printf '%s\n' 'Ran: github-mechanics at not-a-sha' >> "$rh"
head_now=$(g rev-parse HEAD)
at "$repo" close 3 --file "$rh" --result github-mechanics=pass >/dev/null
check "a hand-written Ran line holding no sha is not read: HEAD is stamped" \
  "- github-mechanics: pass at $head_now" "$(grep '^- github-mechanics: ' "$rh")"
was=$(cat "$rh")
check_rc "ran for a name no results section knows is malformed" 2 "$(inrc "$repo" ran nope --file "$rh")"
check_rc "ran with no name is malformed" 2 "$(inrc "$repo" ran --file "$rh")"
check_rc "ran refuses --head, which belongs to close 3" 2 "$(inrc "$repo" ran github-mechanics --head 0123abcd --file "$rh")"
check "a refused ran changed nothing" "$was" "$(cat "$rh")"

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


finish
