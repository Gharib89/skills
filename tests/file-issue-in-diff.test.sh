#!/usr/bin/env bash
# file-issue's in_diff refusal: a find whose title or body cites a path the
# current branch already changes is the PR's own work, not an adjacent find, so
# it is refused unless the caller gives --outside-scope "<reason>". A path is
# cited as a whole token: not preceded by a path character ([A-Za-z0-9_./-],
# bar a leading ./) and not followed by one ([A-Za-z0-9_/-], or a . that opens
# an extension), so `scripts/run` does not cite `scripts/run-file.sh` and a
# sentence's closing `.` does not hide a path. A path in a code span or quote is
# cited. Driven over the Host fake (tests/host-fake.sh) in a throwaway repo.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/file-issue.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$SHIP_FAKE"
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
{
  g init -q "$repo"
  git -C "$repo" remote add origin https://github.com/owner/repo.git
  mkdir -p "$repo/skills/ship/scripts"
  echo x > "$repo/skills/ship/scripts/run-file.sh"; echo x > "$repo/skills/ship/scripts/other.sh"
  g -C "$repo" add -A && g -C "$repo" commit -q -m init
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  g -C "$repo" checkout -q -b feat/thing-1
  echo y > "$repo/skills/ship/scripts/run-file.sh"; mkdir -p "$repo/docs"; echo y > "$repo/docs/n.md"
  g -C "$repo" add -A && g -C "$repo" commit -q -m change
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
body=$work/body.md

reset() { rm -f "$SHIP_FAKE"/*; printf '[]\n' > "$SHIP_FAKE/host_issues_open.1.json"
          jq -n '{number: 9, url: "https://github.com/owner/repo/issues/9"}' > "$SHIP_FAKE/host_issue_create.1.json"; }
run() { # <body text> <title> [flags...]
  printf '%s\n' "$1" > "$body"; local t=$2; shift 2
  ( cd "$repo" && bash "$mech" --title "$t" --body-file "$body" --label needs-triage "$@" 2>/dev/null )
}
calls() { cut -f1 "$SHIP_FAKE/calls" 2>/dev/null | paste -sd' '; }

reset
out=$(run 'run-file.sh drops a line: see skills/ship/scripts/run-file.sh' "an adjacent defect"); rc=$?
check_rc "a body citing a changed path exits 1" 1 "$rc"
check "the error names the path and the way out" \
  'the find cites a path this PR already changes: skills/ship/scripts/run-file.sh; fix it in this PR or pass --outside-scope "<reason>"' "$(jq -r .error <<<"$out")"
check "in_diff lists the path" '["skills/ship/scripts/run-file.sh"]' "$(jq -c .in_diff <<<"$out")"
check "nothing is listed or filed" "" "$(calls)"

reset
out=$(run 'unrelated' "skills/ship/scripts/run-file.sh drops a line"); rc=$?
check_rc "a title citing a changed path exits 1" 1 "$rc"
check "and in_diff names it" '["skills/ship/scripts/run-file.sh"]' "$(jq -c .in_diff <<<"$out")"

reset
out=$(run 'see `docs/n.md` and "skills/ship/scripts/run-file.sh", (skills/ship/scripts/other.sh).' "t"); rc=$?
check_rc "paths in a code span, quotes and parentheses are cited" 1 "$rc"
check "every changed path cited is listed, an unchanged one is not" '["docs/n.md","skills/ship/scripts/run-file.sh"]' "$(jq -c .in_diff <<<"$out")"

reset
out=$(run 'see skills/ship/scripts/run-file.sh' "t" --outside-scope "a different defect in the same file"); rc=$?
check_rc "--outside-scope files the same call" 0 "$rc"
check "it files and echoes the reason" 'true 9 a different defect in the same file' \
  "$(jq -r '"\(.filed) \(.number) \(.outside_scope)"' <<<"$out")"
check "the host sees the list and the create" 'host_issues_open host_issue_create' "$(calls)"
check "the issue body is the caller's file, untouched" "see skills/ship/scripts/run-file.sh" \
  "$(cat "$body")"

reset
out=$(run 'see skills/ship/scripts/other.sh' "t"); rc=$?
check_rc "an unchanged cited path files" 0 "$rc"
check "with no outside_scope key" 'null' "$(jq -c .outside_scope <<<"$out")"

for text in 'skills/ship/scripts/run is a prefix' 'xskills/ship/scripts/run-file.sh a longer path' 'a/skills/ship/scripts/run-file.sh nested' \
            'skills/ship/scripts/run-file.sh.bak a sibling' 'skills/ship/scripts/run-file.shx a longer name' 'docs/n.mdx and docs/n.md/x'; do
  reset
  run "$text" "t" >/dev/null; rc=$?
  check_rc "a near miss is not a citation: $text" 0 "$rc"
done
for text in 'ends the sentence with skills/ship/scripts/run-file.sh.' './docs/n.md leads with ./' 'docs/n.md:12 carries a line' 'docs/n.md, then' 'x=docs/n.md'; do
  reset
  run "$text" "t" >/dev/null; rc=$?
  check_rc "a path bounded by punctuation is a citation: $text" 1 "$rc"
done

reset
out=$(run 'see skills/ship/scripts/run-file.sh' "t" --repo Gharib89/skills); rc=$?
check_rc "--repo skips the check: the find is another repo's" 0 "$rc"

g -C "$repo" checkout -q main
reset
run 'see skills/ship/scripts/run-file.sh' "t" >/dev/null; rc=$?
check_rc "on the base branch there is no diff to cite" 0 "$rc"
g -C "$repo" checkout -q feat/thing-1

reset
run 'x' "t" --outside-scope >/dev/null; rc=$?
check_rc "--outside-scope with no reason is the usage error" 2 "$rc"
run 'x' "t" --outside-scope "" >/dev/null; rc=$?
check_rc "--outside-scope with an empty reason is the usage error" 2 "$rc"

# An unresolved base is a skipped check, not a network call: the in_diff check
# reads origin/HEAD as it is and never asks the origin to refresh it.
shim=$work/shim; mkdir -p "$shim"
printf '#!/bin/sh\ncase "$*" in *set-head*) echo "$*" >> %s/set-head.log ;; esac\nexec %s "$@"\n' "$work" "$(command -v git)" > "$shim/git"
chmod +x "$shim/git"
git -C "$repo" symbolic-ref --delete refs/remotes/origin/HEAD
reset
printf '%s\n' 'see skills/ship/scripts/run-file.sh' > "$body"
( cd "$repo" && PATH=$shim:$PATH bash "$mech" --title t --body-file "$body" --label needs-triage >/dev/null 2>&1 ); rc=$?
check_rc "with no origin/HEAD the check is skipped and the find files" 0 "$rc"
check "and the origin is never asked to refresh its HEAD" "" "$(cat "$work/set-head.log" 2>/dev/null)"
git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# The matcher takes a path as text, not as a pattern: regex characters in a
# path match only themselves.
source skills/ship/scripts/_lib.sh
check "a path with regex characters cites only itself" 'docs/a+b(1).md' \
  "$(ship_paths_cited 'see docs/a+b(1).md and docs/aab1.md' $'docs/a+b(1).md\ndocs/aab1.md\ndocs/a.b.md' | head -1)"
check "an unrelated path is not a wildcard hit" '' "$(ship_paths_cited 'docs/axb.md' 'docs/a.b.md')"

finish
