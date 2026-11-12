#!/usr/bin/env bash
# scripts/read-lint.sh: the shell standard's two read rules over fixtures, and
# the wiring that makes them fail the gate. The edit cases run a throwaway git
# repo holding this repo's check.sh and hook config; without prek on PATH they
# do not run.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
lint() { # <mode> <file>: leaves the exit code in rc and the output in out
  out=$(bash scripts/read-lint.sh "$1" "$2" 2>&1); rc=$?
}
w() { printf '%s\n' "$2" > "$fixture/$1"; }

# --- verdict
w v-bad-if.sh 'x=$(gh api repos/o/r/issues/1)
if jq -e ".state == \"open\"" <<<"$x" >/dev/null; then echo open; fi'
lint verdict "$fixture/v-bad-if.sh"
check_rc "an if jq -e over an unchecked capture fails" 1 "$rc"
case $out in *'v-bad-if.sh:2:'*"capture whose status was never checked"*) check "and names the line and the rule" 0 0 ;; *) check "and names the line and the rule" "line 2 and the rule" "$out" ;; esac

for tool in 'gh api repos/o/r' 'api "$R/issues"' 'nvidia-smi -L' 't3 thread list' 'ffmpeg -i a.mp4' 'gh api repos/o/r && echo got'; do
  w v-bad-bare.sh "raw=\$($tool)
echo \"\$raw\""
  lint verdict "$fixture/v-bad-bare.sh"
  check_rc "a bare capture of '$tool' fails" 1 "$rc"
done
w v-bad-fallback.sh 'a=$(gh api repos/o/r) || a=""
if jq -e ".open" <<<"$a" >/dev/null; then echo open; fi'
lint verdict "$fixture/v-bad-fallback.sh"
check_rc "a || fallback does not validate a later bare jq -e" 1 "$rc"
w v-bad-flags.sh 'a=$(gh api repos/o/r) || a=""
if jq -c -e ".open" <<<"$a" >/dev/null; then echo open; fi'
lint verdict "$fixture/v-bad-flags.sh"
check_rc "jq -c -e is read as jq -e" 1 "$rc"
w v-brace.sh 'a=$(gh api repos/o/r) || { echo unreadable >&2; exit 2; }
if jq -e ".open" <<<"$a" >/dev/null; then echo open; fi'
lint verdict "$fixture/v-brace.sh"
check_rc "a || block that exits is a status check" 0 "$rc"
w v-true.sh 'a=$(gh api repos/o/r) || true
if jq -e ".open" <<<"$a" >/dev/null; then echo open; fi'
lint verdict "$fixture/v-true.sh"
check_rc "|| true is a fallback, so a later bare jq -e still fails" 1 "$rc"
w v-decoy.sh 'a=$(gh api repos/o/r) || a=""
[ -n "$a" ] || exit 2
b=$(gh api repos/o/r); if [ $? -ne 0 ]; then exit 2; fi
c=$(gh api repos/o/r)
if [ $? -ne 0 ]; then exit 2; fi
d=$(jq -r ".a || .b" <<<"$a")
printf "%s\n" "$a" "$b" "$c" "$d"'
lint verdict "$fixture/v-decoy.sh"
check_rc "|| and ? inside a filter, an if on \$?, and an -n test are no violation" 0 "$rc"

w v-ok.sh 'x=$(gh api repos/o/r) || exit 2
if jq -e ".a" <<<"$x" >/dev/null; then echo a; fi
y=$(gh api repos/o/r/pulls \
  -f state=all) \
  || y=""
raw=$(gh api -i "$@" 2>/dev/null); rc=$?
mem=$(nvidia-smi -L)
[ -n "$mem" ] || exit 2
z=$(t3 thread list)
[ "$?" -eq 0 ] || exit 2
w=$(jq -r .a <<<"$x")
q=$(gh api repos/o/r)
if ! jq -e ".a" <<<"$q" >/dev/null; then exit 2; fi
if jq -e ".b" <<<"$q" >/dev/null; then echo b; fi
m=$(gh api -X GET repos/o/r) # read-checked: a missing repo is the answer here
# read-checked: a failed list is the answer here
n=$(gh api repos/o/r/labels)
l=$(jq -c ".a" \
  <<<"$x" \
) || exit 2'
lint verdict "$fixture/v-ok.sh"
check_rc "checked, validated and marked reads pass" 0 "$rc"
check "with no output" "" "$out"

w v-noreason.sh 'a=$(gh api repos/o/r) # read-checked:'
lint verdict "$fixture/v-noreason.sh"
check_rc "a marker with no reason does not exempt" 1 "$rc"

# --- paging
w p-bad.sh 'api "$R/issues?state=open&per_page=100" --jq ".[]"'
lint paging "$fixture/p-bad.sh"
check_rc "a per_page list read with no paging fails" 1 "$rc"
case $out in *'p-bad.sh:1:'*"--paginate"*) check "and names the line and the rule" 0 0 ;; *) check "and names the line and the rule" "line 1 and the rule" "$out" ;; esac

w p-ok.sh 'gh api --paginate "repos/o/r/issues?per_page=100"
x=$(gh api "repos/o/r/issues/1/comments?per_page=100") || x=""
if ! jq -e "type == \"array\" and length < 100" <<<"$x" >/dev/null; then exit 2; fi
# paged: per_page=1 sorted newest first, one item wanted
gh api "repos/o/r/pulls?sort=created&direction=desc&per_page=1" \
  --jq first
gh api repos/o/r/pulls -f per_page=5 # paged: newest five wanted
while :; do
  y=$(gh api "repos/o/r/pulls?per_page=100&page=$p")
  more=$(jq "length == 100" <<<"$y")
done'
lint paging "$fixture/p-ok.sh"
check_rc "paginated, full-page-refusing and marked reads pass" 0 "$rc"
check "with no output" "" "$out"

w p-bad-size.sh 'gh api "repos/o/r/issues?per_page=50" --jq ".[]"
x=1; if [ "${#y}" -lt 3 ]; then echo "$x" | jq "length < 100"; fi'
lint paging "$fixture/p-bad-size.sh"
check_rc "a full-page test for another size does not clear the read" 1 "$rc"
w p-decoy.sh 'gh api "repos/o/r/issues?per_page=100" --jq "if length == 100 then error(\"full\") else . end"
# per_page=100 in a comment is no read'
lint paging "$fixture/p-decoy.sh"
check_rc "a refusal inside the statement clears it, and a comment is no read" 0 "$rc"

w p-noreason.sh 'gh api "repos/o/r/issues?per_page=20" # paged:'
lint paging "$fixture/p-noreason.sh"
check_rc "a marker with no reason does not exempt" 1 "$rc"

check_rc "a missing file is a tooling error" 2 "$(bash scripts/read-lint.sh paging "$fixture/none.sh" >/dev/null 2>&1; echo $?)"

# --- wiring
check "full runs the verdict lint as its own row" 1 \
  "$(grep -c '^read-verdict|scripts/read-lint.sh verdict$' scripts/check.sh)"
check "full runs the paging lint as its own row" 1 \
  "$(grep -c '^list-paging|scripts/read-lint.sh paging$' scripts/check.sh)"
check "the repo's own scripts pass the verdict lint" "0" "$(bash scripts/read-lint.sh verdict >/dev/null 2>&1; echo $?)"
check "the repo's own scripts pass the paging lint" "0" "$(bash scripts/read-lint.sh paging >/dev/null 2>&1; echo $?)"

if ! command -v prek >/dev/null; then
  skipped "read lints at the edit rung: prek is not on PATH"
  finish
fi
r=$fixture/repo
mkdir -p "$r/scripts" "$r/skills/demo/scripts"
cp scripts/check.sh scripts/read-lint.sh scripts/token-limit-check.sh "$r/scripts/"
cp .pre-commit-config.yaml "$r/"
git -C "$r" init -q
edit() { out=$(cd "$r" && CLAUDE_CODE_REMOTE='' bash scripts/check.sh edit "$1" 2>&1); rc=$?; }

cp "$fixture/v-bad-if.sh" "$r/skills/demo/scripts/bad.sh"
edit skills/demo/scripts/bad.sh
check_rc "an edited script with an unchecked jq -e capture fails the edit rung" 1 "$rc"
cp "$fixture/p-bad.sh" "$r/skills/demo/scripts/bad.sh"
edit skills/demo/scripts/bad.sh
check_rc "an edited script with an unpaged list read fails the edit rung" 1 "$rc"
printf '#!/usr/bin/env bash\nx=$(gh api repos/o/r) || exit 2\nprintf "%%s\\n" "$x"\n' > "$r/skills/demo/scripts/good.sh"
edit skills/demo/scripts/good.sh
check_rc "a conforming script passes" 0 "$rc"
case $out in *'"verdict":"pass"'*) check "and the rung read it" 0 0 ;; *) check "and the rung read it" 'verdict pass' "$out" ;; esac

finish
