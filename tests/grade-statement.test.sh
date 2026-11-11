#!/usr/bin/env bash
# scripts/check-grade-statement.sh: a PR whose diff changes a skill's description,
# or a mechanic's usage line or `stdout:` header under a non-feat title, states its
# grade in a `Grade:` line under "Special things to note". The seam is the
# script's environment (PR_TITLE, PR_BODY, PR_BASE, PR_ROOT), so each case builds
# a throwaway repo, commits a base and a change on a branch, and drives it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <case> <setup command run in the branch before its commit>: a repo whose
# `main` holds a skill and a mechanic, and whose `pr` branch holds the change
# the command makes. Prints the repo path.
repo() {
  local r="$fixture/$1"; shift
  mkdir -p "$r/skills/demo/scripts" "$r/.claude/skills/demo/scripts"
  printf -- '---\nname: demo\ndescription: Do the demo. Use when the user asks for a demo.\n---\n\n# demo\n' > "$r/skills/demo/SKILL.md"
  printf '#!/usr/bin/env bash\n# stdout: {ok}\nusage="usage: m <x>"\n' > "$r/skills/demo/scripts/m.sh"
  cp "$r/skills/demo/SKILL.md" "$r/.claude/skills/demo/SKILL.md"
  cp "$r/skills/demo/scripts/m.sh" "$r/.claude/skills/demo/scripts/m.sh"
  git -C "$r" init -q -b main
  git -C "$r" add -A
  git -C "$r" -c user.name=t -c user.email=t@t commit -q -m base
  git -C "$r" checkout -q -b pr
  ( cd "$r" && eval "$1" )
  git -C "$r" add -A
  git -C "$r" -c user.name=t -c user.email=t@t commit -q -m change
  printf '%s' "$r"
}
# <repo> <title> <body>: leaves the exit code in `rc` and stdout in `out`.
grade() {
  out=$(PR_ROOT=$1 PR_BASE=main PR_TITLE=$2 PR_BODY=$3 bash scripts/check-grade-statement.sh 2>/dev/null); rc=$?
}
with_line=$'## Why\n\nx\n\n## Special things to note\n\n- 🟢 Door: two-way. Blast radius: none.\n- Grade: a routing condition was added, so minor.\n\n## Needs attention\n\nNone.\n'
without_line=$'## Why\n\nx\n\n## Special things to note\n\n- 🟢 Door: two-way. Blast radius: none.\n\n## Needs attention\n\nNone.\n'
line_elsewhere=$'## Why\n\nGrade: patch\n\n## Special things to note\n\n- 🟢 Door: two-way.\n\n## Needs attention\n\nNone.\n'

desc='sed -i "s/^description:.*/description: Do the demo. Use when the user asks for a demo or a trial./" skills/demo/SKILL.md; cp skills/demo/SKILL.md .claude/skills/demo/SKILL.md'
r=$(repo desc "$desc")
grade "$r" 'fix(demo): reword' "$without_line"
check_rc "a changed description with no Grade: line fails" 1 "$rc"
check "naming the changed skill file and the line to add" 1 "$(printf '%s\n' "$out" | grep -c 'skills/demo/SKILL.md.*Grade:')"
check "the skill and its derived copy are one change, named once" 1 "$(printf '%s\n' "$out" | grep -c 'SKILL.md')"
grade "$r" 'fix(demo): reword' "$with_line"
check_rc "the same diff passes once the Grade: line is under the heading" 0 "$rc"
grade "$r" 'feat(demo): reword' "$without_line"
check_rc "a feat title does not excuse a changed description" 1 "$rc"
grade "$r" 'fix(demo): reword' "$line_elsewhere"
check_rc "a Grade: line under another heading does not count" 1 "$rc"
grade "$r" 'fix(demo): reword' $'## Special things to note\n\n<!-- Grade: patch -->\n\n## Needs attention\n'
check_rc "a Grade: line inside an HTML comment does not count" 1 "$rc"

# Wrapping the same description differently is no change.
r=$(repo rewrap 'printf -- "---\nname: demo\ndescription: >-\n  Do the demo. Use when the user asks for a demo.\n---\n\n# demo\n" > skills/demo/SKILL.md')
grade "$r" 'fix(demo): rewrap' "$without_line"
check_rc "a description wrapped differently, unchanged in content, passes with no line" 0 "$rc"

# Prose below the frontmatter is not the description.
r=$(repo body-prose 'echo more >> skills/demo/SKILL.md')
grade "$r" 'fix(demo): prose' "$without_line"
check_rc "a change to the skill's prose alone passes with no line" 0 "$rc"

usage='sed -i "s/^usage=.*/usage=\"usage: m <x> [--y <z>]\"/" skills/demo/scripts/m.sh; cp skills/demo/scripts/m.sh .claude/skills/demo/scripts/m.sh'
r=$(repo usage "$usage")
grade "$r" 'fix(demo): add a flag' "$without_line"
check_rc "a changed usage line under a fix title with no Grade: line fails" 1 "$rc"
check "naming the mechanic" 1 "$(printf '%s\n' "$out" | grep -c 'skills/demo/scripts/m.sh')"
grade "$r" 'fix(demo): add a flag' "$with_line"
check_rc "and passes with the line" 0 "$rc"
grade "$r" 'feat(demo): add a flag' "$without_line"
check_rc "a feat PR with the same diff passes with no line" 0 "$rc"

r=$(repo stdout 'sed -i "s/^# stdout:.*/# stdout: {ok, extra}/" skills/demo/scripts/m.sh')
grade "$r" 'chore(demo): tidy' "$without_line"
check_rc "a changed stdout: header under a chore title fails" 1 "$rc"

r=$(repo stdout-cont 'printf "#   second line\n" >> skills/demo/scripts/m.sh; sed -i "2a #   more fields" skills/demo/scripts/m.sh')
grade "$r" 'fix(demo): tidy' "$without_line"
check_rc "a continuation line of the stdout: header counts" 1 "$rc"

r=$(repo body-code 'printf "echo hi\n" >> skills/demo/scripts/m.sh')
grade "$r" 'fix(demo): code' "$without_line"
check_rc "a change to a mechanic's code alone passes with no line" 0 "$rc"

# A diff touching neither passes with no line, whatever the title.
r=$(repo neither 'echo x > skills/demo/notes.md')
grade "$r" 'chore(demo): notes' "$without_line"
check_rc "a diff with neither change passes with no line" 0 "$rc"

# The derived copy alone is no change of the skill.
r=$(repo derived-only 'sed -i "s/^description:.*/description: Other./" .claude/skills/demo/SKILL.md')
grade "$r" 'fix(demo): copy' "$without_line"
check_rc "a derived copy changing alone is not counted" 0 "$rc"

# A new skill's description is one too.
r=$(repo new-skill 'mkdir -p skills/new; printf -- "---\nname: new\ndescription: A new one.\n---\n" > skills/new/SKILL.md')
grade "$r" 'feat(new): add' "$without_line"
check_rc "a new skill's description needs the line" 1 "$rc"

# Tooling.
out=$(PR_ROOT=$r PR_TITLE='fix: x' PR_BODY='' bash scripts/check-grade-statement.sh 2>/dev/null); rc=$?
check_rc "no base ref is tooling, exit 2" 2 "$rc"

finish
