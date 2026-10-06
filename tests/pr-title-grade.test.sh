#!/usr/bin/env bash
# The grade rule at the two mechanics that set a PR title: open-pr and
# update-pr-title refuse a title whose Conventional-Commit type grades below the
# `Grade:` the Run file records (docs/contributing/standards/release.md, ADR
# 0005), before any push or host write. Driven over the Host fake
# (tests/host-fake.sh) in a throwaway repo whose origin names GitHub and whose
# pushes land in a local bare repository, so "no push" is read off that bare repo
# and "no host write" off the fake's calls log. ship_title_grade, the title to
# grade map, is held directly at the end.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
T=$'\t'

open=$PWD/skills/ship/scripts/open-pr.sh
retitle=$PWD/skills/ship/scripts/update-pr-title.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; bare=$work/origin.git; export SHIP_FAKE=$work/fake
mkdir -p "$SHIP_FAKE"
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
{
  g init -q --bare "$bare"
  g init -q "$repo"
  git -C "$repo" remote add origin https://github.com/owner/repo.git
  git -C "$repo" config "url.$bare.pushInsteadOf" https://github.com/owner/repo.git
  g -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  g -C "$repo" checkout -q -b feat/thing-7
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
printf 'body\n' > "$work/body.md"
runfile=$repo/.git/ship/ship-7/run.md

grade() { # <word|none>: the Run file's recorded grade
  rm -rf "$repo/.git/ship"
  [ "$1" = none ] && return 0
  mkdir -p "$repo/.git/ship/ship-7"
  printf '# Run 7\n\n## Grade\n\nGrade: %s\n\n## Notes\n' "$1" > "$runfile"
}
reset() { rm -f "$SHIP_FAKE"/*; git -C "$bare" update-ref -d refs/heads/feat/thing-7 2>/dev/null; }
opn()   { ( cd "$repo" && bash "$open" "${1:-7}" --title "$2" --body-file "$work/body.md" 2>/dev/null ); }
pushed() { git -C "$bare" rev-parse -q --verify refs/heads/feat/thing-7 >/dev/null && echo pushed || echo none; }

# --- open-pr ---------------------------------------------------------------
reset; grade minor
out=$(opn 7 "fix(ship): a small thing"); rc=$?
check_rc "open-pr: a fix title against Grade: minor exits 1" 1 "$rc"
check "open-pr: it names the recorded grade, the title's type and the type to use" \
  'title type fix grades patch, below the recorded Grade: minor; retitle as feat(...)' "$(jq -r .error <<<"$out")"
check "open-pr: nothing is pushed" none "$(pushed)"
check "open-pr: no host call is made" "" "$(cat "$SHIP_FAKE/calls" 2>/dev/null)"

reset; grade minor
out=$(opn 7 "feat(ship): a new thing"); rc=$?
check_rc "open-pr: a feat title against Grade: minor exits 0" 0 "$rc"
check "open-pr: it pushes and creates" "pushed host_pr_create" "$(pushed) $(cut -f1 "$SHIP_FAKE/calls" | paste -sd' ')"

reset; grade none
opn 7 "fix(ship): a small thing" >/dev/null; rc=$?
check_rc "open-pr: a Run file with no Grade line is not checked" 0 "$rc"

reset; grade patch
opn 7 "docs: reword" >/dev/null; rc=$?
check_rc "open-pr: Grade: patch accepts any type" 0 "$rc"

reset; grade breaking
out=$(opn 7 "refactor(ship): rename a key"); rc=$?
check_rc "open-pr: a refactor title against Grade: breaking exits 1" 1 "$rc"
check "open-pr: and names the breaking grade" \
  'title type refactor grades patch, below the recorded Grade: breaking; retitle as feat(...)' "$(jq -r .error <<<"$out")"
reset
opn 7 "feat(ship): rename a key" >/dev/null; rc=$?
check_rc "open-pr: a feat title satisfies Grade: breaking on a 0.x skill" 0 "$rc"
reset
opn 7 "feat(ship)!: rename a key" >/dev/null; rc=$?
check_rc "open-pr: a ! title satisfies Grade: breaking" 0 "$rc"
reset; grade minor
opn 7 "fix!: rename a key" >/dev/null; rc=$?
check_rc "open-pr: a ! title satisfies Grade: minor" 0 "$rc"

reset; grade minor
opn 7 "update the thing" >/dev/null; rc=$?
check_rc "open-pr: a title that is no Conventional Commit is bump-guard's, not this check's" 0 "$rc"

reset; grade bogus
opn 7 "fix: x" >/dev/null; rc=$?
check_rc "open-pr: an unknown Grade word is no check" 0 "$rc"

reset; grade minor
opn none "fix: x" >/dev/null; rc=$?
check_rc "open-pr: issue none is never checked" 0 "$rc"

# --- update-pr-title -------------------------------------------------------
# The read-back (second host_pr_get) answers with the title the call sets.
pr_get() { # <head_ref> <old title> <new title>
  jq -n --arg h "$1" --arg t "$2" '{title:$t, head_ref:$h}' > "$SHIP_FAKE/host_pr_get.1.json"
  jq -n --arg h "$1" --arg t "$3" '{title:$t, head_ref:$h}' > "$SHIP_FAKE/host_pr_get.2.json"
}
rtl() { ( cd "$repo" && bash "$retitle" 12 --title "$1" 2>/dev/null ); }

reset; grade minor; pr_get feat/thing-7 "feat(ship): old" "fix(ship): new"
out=$(rtl "fix(ship): new"); rc=$?
check_rc "update-pr-title: a fix title against the branch issue's Grade: minor exits 1" 1 "$rc"
check "update-pr-title: it names the recorded grade, the type and the type to use" \
  'title type fix grades patch, below the recorded Grade: minor; retitle as feat(...)' "$(jq -r .error <<<"$out")"
check "update-pr-title: the host is read and never written" "host_pr_get${T}12" "$(cat "$SHIP_FAKE/calls")"

reset; grade minor; pr_get feat/thing-7 "fix(ship): old" "feat(ship): new"
out=$(rtl "feat(ship): new"); rc=$?
check_rc "update-pr-title: a feat title against Grade: minor exits 0" 0 "$rc"
check "update-pr-title: and writes" 'host_pr_get host_pr_set_title host_pr_get' "$(cut -f1 "$SHIP_FAKE/calls" | paste -sd' ')"

reset; grade minor; pr_get feat/thing-7 "fix(ship): same" "fix(ship): same"
rtl "fix(ship): same" >/dev/null; rc=$?
check_rc "update-pr-title: a title unchanged and under-graded is refused too" 1 "$rc"

reset; grade minor; pr_get main "fix(ship): old" "fix(ship): new"
rtl "fix(ship): new" >/dev/null; rc=$?
check_rc "update-pr-title: a head_ref with no -<issue> suffix is not checked" 0 "$rc"

reset; grade none; pr_get feat/thing-7 "fix(ship): old" "fix(ship): new"
rtl "fix(ship): new" >/dev/null; rc=$?
check_rc "update-pr-title: no Grade line is not checked" 0 "$rc"

reset; grade breaking; pr_get feat/thing-7 "fix(ship): old" "feat(ship)!: new"
rtl "feat(ship)!: new" >/dev/null; rc=$?
check_rc "update-pr-title: feat! against Grade: breaking exits 0" 0 "$rc"

# --- ship_title_grade ------------------------------------------------------
source skills/ship/scripts/_lib.sh
tg() { check "ship_title_grade: $1" "$2" "$(ship_title_grade "$1")"; }
tg "feat: x" minor
tg "feat(ship): x" minor
tg "feat(ship)!: x" breaking
tg "fix!: x" breaking
tg "fix(ship): x" patch
tg "chore(release): ship v0.17.0" patch
tg "revert: x" patch
tg "not conventional" ""
tg "feat x" ""
tg "(ship): x" ""

finish
