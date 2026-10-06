#!/usr/bin/env bash
# skills/ship/scripts/dropped-lines.sh: which removed lines of the diff have no
# matching added line anywhere in it? The seam is the script's CLI, driven end to
# end against throwaway fixture repos whose `origin/HEAD` is set by hand so no
# remote is needed. Every case builds its own repo from a base commit, so a case
# cannot lean on what an earlier one left.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

script=$PWD/skills/ship/scripts/dropped-lines.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

g() { git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }

# mkrepo <name> makes an empty repo at $T/<name>; the caller writes its base
# files, then commit_base commits them and points origin/HEAD at that commit.
mkrepo() {
  repo=$T/$1
  git init -q -b main "$repo"
}
commit_base() {
  g -C "$repo" add -A && g -C "$repo" commit -qm base
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
commit_all() { g -C "$repo" add -A && g -C "$repo" commit -qm "${1:-work}"; }
# run [<args>...]: the script's stdout, compact, from the fixture repo.
run() { (cd "$repo" && bash "$script" "$@" 2>/dev/null | jq -c .); }
rc_of() { (cd "$repo" && bash "$script" "$@" >/dev/null 2>&1); printf '%s' "$?"; }
# ids: the block ids, space-joined.
ids() { jq -r '[.blocks[].id] | join(" ")' <<<"$1"; }

five='alpha one
beta two
gamma three
delta four
epsilon five'

# --- a move is not a drop ----------------------------------------------------

mkrepo move
printf 'head\n%s\ntail\n' "$five" > "$repo/a.sh"
printf 'other\n' > "$repo/b.sh"
commit_base
printf 'head\ntail\n' > "$repo/a.sh"
printf 'other\n%s\n' "$five" > "$repo/b.sh"
commit_all move
out=$(run)
check "a pure move of a 5-line block between files reports nothing" '[]' "$(jq -c .blocks <<<"$out")"
check_rc "a run with nothing dropped exits 0" 0 "$(rc_of)"

# The same block, re-indented where it landed: matching trims both ends.
mkrepo reindent
printf 'head\n%s\ntail\n' "$five" > "$repo/a.sh"
commit_base
printf 'head\ntail\n' > "$repo/a.sh"
printf '%s\n' "$five" | sed 's/^/    /; s/$/  /' > "$repo/b.sh"
commit_all move
check "a moved block re-indented and padded still matches" '[]' "$(jq -c .blocks <<<"$(run)")"

# A move into a file git has not been told about yet is still a move.
mkrepo untracked
printf 'head\n%s\ntail\n' "$five" > "$repo/a.sh"
commit_base
printf 'head\ntail\n' > "$repo/a.sh"
printf '%s\n' "$five" > "$repo/new.sh"
check "a move into an untracked new file counts as matched" '[]' "$(jq -c .blocks <<<"$(run)")"

# --- a deletion is a drop ----------------------------------------------------

mkrepo drop
printf 'head\n%s\ntail\n' "$five" > "$repo/a.sh"
commit_base
printf 'head\ntail\n' > "$repo/a.sh"
commit_all drop
out=$(run)
check "deleting a 5-line block reports exactly that block" \
  '[{"id":"a.sh:2","file":"a.sh","line":2,"lines":5,"text":["alpha one","beta two","gamma three","delta four","epsilon five"]}]' \
  "$(jq -c .blocks <<<"$out")"
check "the verdict names the base it diffed against" \
  "$(git -C "$repo" rev-parse refs/remotes/origin/main)" "$(jq -r .base <<<"$out")"
check_rc "a run that finds a drop still exits 0" 0 "$(rc_of)"

# The text is capped at five lines.
mkrepo long
printf 'head\n%s\nfive six\nsix seven\ntail\n' "$five" > "$repo/a.sh"
commit_base
printf 'head\ntail\n' > "$repo/a.sh"
commit_all drop
out=$(run)
check "a 7-line drop counts every line" 7 "$(jq '.blocks[0].lines' <<<"$out")"
check "its text shows the first five" 5 "$(jq '.blocks[0].text | length' <<<"$out")"

# Below the threshold it is an edit, not a drop.
mkrepo two
printf 'head\nalpha one\nbeta two\ntail\n' > "$repo/a.sh"
commit_base
printf 'head\ntail\n' > "$repo/a.sh"
commit_all drop
check "a 2-line deletion reports nothing" '[]' "$(jq -c .blocks <<<"$(run)")"

# Exactly at the threshold.
mkrepo three
printf 'head\nalpha one\nbeta two\ngamma three\ntail\n' > "$repo/a.sh"
commit_base
printf 'head\ntail\n' > "$repo/a.sh"
commit_all drop
check "a 3-line deletion is a block" "a.sh:2" "$(ids "$(run)")"

# Replacement text that differs is a drop: a reworded block needs a disposition.
mkrepo reword
printf 'head\n%s\ntail\n' "one a
two b
three c
four d" > "$repo/a.sh"
commit_base
printf 'head\n%s\ntail\n' "one x
two y
three z
four w" > "$repo/a.sh"
commit_all reword
check "an edit replacing 4 lines by 4 different lines reports a block" "a.sh:2" "$(ids "$(run)")"

# --- how a run of removed lines is cut ---------------------------------------

# A matched line in the middle ends the run; the two halves are judged apart.
mkrepo split
printf 'keep\nr1 one\nr2 two\nr3 three\nshared line\nr4 four\nr5 five\ntail\n' > "$repo/a.sh"
commit_base
printf 'keep\ntail\nshared line\n' > "$repo/a.sh"
commit_all split
check "a matched line splits the run: 3 unmatched before it is one block, 2 after is none" \
  "a.sh:2" "$(ids "$(run)")"

# A blank removed line inside a run does not end it.
mkrepo blank
printf 'keep\nr1 one\n\nr2 two\n   \nr3 three\ntail\n' > "$repo/a.sh"
commit_base
printf 'keep\ntail\n' > "$repo/a.sh"
commit_all blank
out=$(run)
check "blank removed lines do not break a run" "a.sh:2" "$(ids "$out")"
check "and do not count toward its size" 3 "$(jq '.blocks[0].lines' <<<"$out")"
check "nor appear in its text" '["r1 one","r2 two","r3 three"]' "$(jq -c '.blocks[0].text' <<<"$out")"

# Removed lines that begin `--` render as `--- ...` in the diff, which is also
# what a file header looks like.
mkrepo dashes
printf 'keep\n-- one\n-- two\n-- three\n-- four\ntail\n' > "$repo/a.sql"
commit_base
printf 'keep\ntail\n' > "$repo/a.sql"
commit_all dashes
check "removed lines that look like diff headers are still lines" \
  '[{"id":"a.sql:2","file":"a.sql","line":2,"lines":4,"text":["-- one","-- two","-- three","-- four"]}]' \
  "$(jq -c .blocks <<<"$(run)")"

# Two separate drops in one file are two blocks, each with its own first line.
mkrepo twoblocks
printf 'top\na1 x\na2 x\na3 x\nmid1\nmid2\nmid3\nb1 x\nb2 x\nb3 x\nend\n' > "$repo/a.sh"
commit_base
printf 'top\nmid1\nmid2\nmid3\nend\n' > "$repo/a.sh"
commit_all two
check "two drops in one file are two blocks" "a.sh:2 a.sh:8" "$(ids "$(run)")"

# A deleted file: its lines are removed, and the id carries its old path.
mkrepo deleted
mkdir "$repo/dir"
printf 'one a\ntwo b\nthree c\nfour d\n' > "$repo/dir/gone.sh"
printf 'stay\n' > "$repo/stay.sh"
commit_base
git -C "$repo" rm -q dir/gone.sh
commit_all rm
check "a wholly deleted file is a drop under its old path" "dir/gone.sh:1" "$(ids "$(run)")"

# A renamed file with its content intact is a move.
mkrepo renamed
printf 'one a\ntwo b\nthree c\nfour d\n' > "$repo/old.sh"
commit_base
git -C "$repo" mv old.sh new.sh
commit_all mv
check "a rename keeping its content reports nothing" '[]' "$(jq -c .blocks <<<"$(run)")"

# A rename that also drops a block reads as a delete plus an add: the block is
# found where it was, under the old path.
mkrepo renamed2
pad='p1 a
p2 b
p3 c
p4 d
p5 e
p6 f
p7 g
p8 h'
printf 'top\nr1 one\nr2 two\nr3 three\n%s\n' "$pad" > "$repo/old.sh"
commit_base
git -C "$repo" mv old.sh new.sh
printf 'top\n%s\n' "$pad" > "$repo/new.sh"
commit_all mv
check "a rename that drops a block reports it under the old path" "old.sh:2" "$(ids "$(run)")"

# --- the diff is against the working tree ------------------------------------

mkrepo uncommitted
printf 'head\n%s\ntail\n' "$five" > "$repo/a.sh"
commit_base
printf 'head\ntail\n' > "$repo/a.sh"
check "an uncommitted deletion is seen" "a.sh:2" "$(ids "$(run)")"
g -C "$repo" add -A
check "and a staged one" "a.sh:2" "$(ids "$(run)")"

# --- --base ------------------------------------------------------------------

mkrepo basearg
printf 'head\n%s\ntail\n' "$five" > "$repo/a.sh"
printf 'x\ny\nz\nw\nv\n' > "$repo/b.sh"
commit_base
printf 'head\ntail\n' > "$repo/a.sh"
commit_all first
mid=$(git -C "$repo" rev-parse HEAD)
: > "$repo/b.sh"
commit_all second
check "by default every commit since the merge base is in" "a.sh:2 b.sh:1" "$(ids "$(run)")"
check "--base narrows the diff to what came after it" "b.sh:1" "$(ids "$(run --base "$mid")")"
check "--base takes a ref name" "b.sh:1" "$(ids "$(run --base HEAD~1)")"
check "--base is reported as the commit it named" "$mid" "$(jq -r .base <<<"$(run --base "$mid")")"
check_rc "--base naming no commit is tooling" 2 "$(rc_of --base no-such-ref)"

# --- help, bad calls ---------------------------------------------------------

mkrepo calls
printf 'a\n' > "$repo/a.sh"
commit_base
help=$(cd "$T" && bash "$script" --help 2>"$T/err"); rc=$?
check_rc "--help exits 0 from a directory that is no repository" 0 "$rc"
check "--help opens with the usage line" 'usage: dropped-lines [--base <ref>]' "$(sed -n 1p <<<"$help")"
check "--help names its stdout fields next" 'stdout:' "$(sed -n 2p <<<"$help" | cut -c1-7)"
check "--help writes nothing on stderr" "" "$(cat "$T/err")"

out=$(cd "$repo" && bash "$script" --nope 2>/dev/null); rc=$?
check_rc "an unknown flag exits 2" 2 "$rc"
check "an unknown flag prints one JSON object carrying the usage line" \
  'usage: dropped-lines [--base <ref>]' "$(jq -r '.error' <<<"$out")"
check_rc "--base with no value exits 2" 2 "$(rc_of --base)"
check_rc "--base taking a flag as its value exits 2" 2 "$(rc_of --base --x)"
check_rc "a positional argument exits 2" 2 "$(rc_of stray)"

out=$(cd "$T" && bash "$script" 2>/dev/null); rc=$?
check_rc "outside a git repository exits 2" 2 "$rc"
check "and says so as JSON" "true" "$(jq -r 'has("error")' <<<"$out")"

# No origin/HEAD and no --base: nothing to diff against.
git -C "$repo" symbolic-ref --delete refs/remotes/origin/HEAD
check_rc "no origin/HEAD and no --base is tooling" 2 "$(rc_of)"
check "--base needs no origin/HEAD" '[]' "$(jq -c .blocks <<<"$(run --base HEAD)")"

finish
