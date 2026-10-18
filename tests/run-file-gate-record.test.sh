#!/usr/bin/env bash
# Split by behaviour from tests/run-file-record.test.sh: the gate record cases.
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
