#!/usr/bin/env bash
# read-pr's `outline_missing`: the changed paths the PR body's `## Change
# outline` section does not mention. Driven over the Host fake
# (tests/host-fake.sh) in a throwaway repo with a base branch and a PR branch, so
# the three-dot diff is a real one. A path is mentioned by its full path or its
# basename when no other changed path shares it; a derived copy under
# .claude/skills/ mirrors its source, so the source's mention covers it;
# lockfiles and changelogs are never expected.
# Off the PR's own branch the paths cannot be known, and the field is null.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/read-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$SHIP_FAKE"
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
{
  g init -q "$repo"
  git -C "$repo" remote add origin https://github.com/owner/repo.git
  g -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  g -C "$repo" checkout -q -b fix/thing-1
  mkdir -p "$repo/skills/ship/scripts" "$repo/.claude/skills/ship/scripts" "$repo/docs"
  for f in skills/ship/scripts/a.sh .claude/skills/ship/scripts/a.sh skills/ship/scripts/b.sh docs/n.md skills-lock.json skills/ship/CHANGELOG.md; do
    echo x > "$repo/$f"
  done
  g -C "$repo" add -A && g -C "$repo" commit -q -m change
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh

# No network: an unresolved base would otherwise ask the fake origin for its HEAD.
run()   { ( cd "$repo" && GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 bash "$mech" 7 ); }
reset() { rm -f "$SHIP_FAKE"/*; }
pr_body() { # <body> [<head_ref>]
  jq -n --arg b "$1" --arg h "${2:-fix/thing-1}" \
    '{number:7,url:"u",title:"t",body:$b,head_sha:"d",head_ref:$h,base_ref:"main",draft:false,state:"open",mergeable:"clean"}' \
    > "$SHIP_FAKE/host_pr_get.1.json"
}
missing() { run | jq -c .outline_missing; }

all=$'## Why the change\nx\n\n## Change outline\n\n```diff\n+ skills/ship/scripts/a.sh\n+ b.sh\n```\n- docs/n.md\n\n## Special things to note\nnone\n'
reset; pr_body "$all"
check "every changed path mentioned leaves nothing missing" '[]' "$(missing)"

reset; pr_body "${all/- docs\/n.md/- nothing else}"
check "a path the section does not mention is listed" '["docs/n.md"]' "$(missing)"

reset; pr_body "${all/b.sh/c.sh}"
check "a basename that differs is not a mention" '["skills/ship/scripts/b.sh"]' "$(missing)"

reset; pr_body "${all/skills\/ship\/scripts\/a.sh/a.sh}"
check "a basename alone is a mention, and covers the derived copy beside its source" '[]' "$(missing)"

reset; pr_body $'## Change outline\nonly skills/ship/scripts/a.sh, b.sh and docs/n.md\n'
check "the source's mention covers its .claude/skills derived copy" '[]' "$(missing)"

reset; pr_body $'## Change outline\nb.sh and docs/n.md\n'
out=$(missing)
check "a source and its derived copy, both unmentioned, are both listed" \
  '[".claude/skills/ship/scripts/a.sh","skills/ship/scripts/a.sh"]' "$out"

reset; pr_body $'## Why the change\nskills-lock.json CHANGELOG.md a.sh b.sh n.md\n'
check "a body with no Change outline heading misses every expected path" \
  '[".claude/skills/ship/scripts/a.sh","docs/n.md","skills/ship/scripts/a.sh","skills/ship/scripts/b.sh"]' "$(missing)"

reset; pr_body $'## Special things to note\n## Change outline\n## Why the change\na.sh b.sh n.md\n'
check "text outside the outline section is no mention" \
  '[".claude/skills/ship/scripts/a.sh","docs/n.md","skills/ship/scripts/a.sh","skills/ship/scripts/b.sh"]' "$(missing)"

reset; pr_body $'```\n## Change outline\n```\na.sh b.sh n.md\n'
check "a heading inside a fence is no section" \
  '[".claude/skills/ship/scripts/a.sh","docs/n.md","skills/ship/scripts/a.sh","skills/ship/scripts/b.sh"]' "$(missing)"

reset; pr_body "$all" some/other-branch
check "off the PR's own branch the paths are not known" 'null' "$(missing)"
check "and the rest of the answer still stands" '["Why the change","Change outline","Special things to note"]' \
  "$(run | jq -c .headings)"

# An unresolved base leaves the field null: origin/HEAD is read as it is, and the
# origin is never asked to refresh it.
shim=$work/shim; mkdir -p "$shim"
printf '#!/bin/sh\ncase "$*" in *set-head*) echo "$*" >> %s/set-head.log ;; esac\nexec %s "$@"\n' "$work" "$(command -v git)" > "$shim/git"
chmod +x "$shim/git"
git -C "$repo" symbolic-ref --delete refs/remotes/origin/HEAD
reset; pr_body "$all"
check "with no origin/HEAD the paths are not known" 'null' "$(PATH=$shim:$PATH missing)"
check "and the origin is never asked to refresh its HEAD" "" "$(cat "$work/set-head.log" 2>/dev/null)"
git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# A mention is the whole path or a basename that names one changed file, bounded
# the way ship_paths_cited bounds a path, so a longer token or a shared name does
# not cover a file it is not.
g -C "$repo" checkout -q -b fix/names-1
mkdir -p "$repo/tests" "$repo/skills/x" "$repo/skills/y" "$repo/.claude/skills/x"
for f in skills/ship/scripts/_lib.sh tests/lib.sh skills/x/SKILL.md skills/y/SKILL.md .claude/skills/x/SKILL.md; do
  echo y > "$repo/$f"
done
g -C "$repo" add -A && g -C "$repo" commit -q -m names >/dev/null 2>&1
names=$'## Change outline\n'
# These mentions cover the files the earlier fixture commit changed.
names_base="a.sh b.sh docs/n.md"$'\n'

reset; pr_body "$names$names_base"$'`_lib.sh` skills/x/SKILL.md skills/y/SKILL.md\n' fix/names-1
check "a _lib.sh mention does not cover tests/lib.sh (a partial token)" '["tests/lib.sh"]' "$(missing)"

reset; pr_body "$names$names_base"$'_lib.sh tests/lib.sh SKILL.md\n' fix/names-1
check "a bare SKILL.md covers neither of two changed SKILL.md files" \
  '[".claude/skills/x/SKILL.md","skills/x/SKILL.md","skills/y/SKILL.md"]' "$(missing)"

reset; pr_body "$names$names_base"$'_lib.sh tests/lib.sh skills/y/SKILL.md\n' fix/names-1
check "a full path covers only that SKILL.md" \
  '[".claude/skills/x/SKILL.md","skills/x/SKILL.md"]' "$(missing)"

reset; pr_body "$names$names_base"$'_lib.sh tests/lib.sh skills/y/SKILL.md skills/x/SKILL.md\n' fix/names-1
check "a source's full path covers its derived copy" '[]' "$(missing)"

reset; pr_body "$names$names_base"$'`_lib.sh`, `tests/lib.sh`, `skills/x/SKILL.md` and `skills/y/SKILL.md`.\n' fix/names-1
check "paths in code spans and before a closing period still count" '[]' "$(missing)"

reset; pr_body "$names$names_base"$'x_lib.sh tests/lib.sh skills/x/SKILL.md skills/y/SKILL.md\n' fix/names-1
check "a longer token that ends in the basename is no mention" '["skills/ship/scripts/_lib.sh"]' "$(missing)"
g -C "$repo" checkout -q fix/thing-1

g -C "$repo" checkout -q main
reset; pr_body "$all"
check "a checkout on another branch is null, not a diff against nothing" 'null' "$(missing)"
g -C "$repo" checkout -q fix/thing-1

git -C "$repo" update-ref -d refs/remotes/origin/HEAD
reset; pr_body "$all"
check "an unresolvable base is null" 'null' "$(missing)"

finish
