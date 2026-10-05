#!/usr/bin/env bash
# scripts/glossary-warn.sh: a warning per `_Avoid_` word of GLOSSARY.md found in
# the lines a diff adds to markdown. A warning never fails the run, so every
# case but the tooling ones asserts exit 0 and the printed line.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
script=$PWD/scripts/glossary-warn.sh

# Acts on $d, the caller's own (mkrepo's, while it builds one).
git_() { git -C "$d" -c user.name=t -c user.email=t@t.invalid "$@"; }

# <name>: a repo on branch main holding a glossary and a doc, with a feature
# branch checked out; prints its path. Cases then add a head commit.
mkrepo() {
  local d="$fixture/$1"
  mkdir -p "$d/docs"
  git -C "$d" init -q -b main
  cat > "$d/GLOSSARY.md" <<'G'
# Glossary

**Ship**:
The skill that drives one issue.
_Avoid_: pipeline, deliver, `autopilot`

**Verdict**:
The local gate's one answer.
_Avoid_: result, report (the word `report` alone), gate output, raw `gh` call (a write)

**Empty**:
Nothing to avoid.
_Avoid_:
G
  printf 'line one\n' > "$d/docs/a.md"
  git_ add -A; git_ commit -q -m base
  git_ checkout -q -b feature
  printf '%s' "$d"
}
# <repo> [args...]
run() { local r=$1; shift; (cd "$r" && bash "$script" "$@" 2>"$fixture/err"); }
rc_of() { local r=$1; shift; (cd "$r" && bash "$script" "$@" >/dev/null 2>&1); printf '%s' "$?"; }

d=$(mkrepo hit)
printf 'line one\nship the pipeline today\n' > "$d/docs/a.md"; git_ commit -q -am head
check "an added avoided word prints one warning line" \
  'glossary: docs/a.md:2: "pipeline" is on the _Avoid_ list of Ship; use Ship if the word names it' "$(run "$d" main)"
check_rc "a warning does not fail the run" 0 "$(rc_of "$d" main)"

# Backticks, a parenthetical and case are the glossary's decoration, not the word.
d=$(mkrepo decoration)
printf 'line one\nAUTOPILOT here\na raw gh call there\nthe gate output\n' > "$d/docs/a.md"; git_ commit -q -am head
check "case is ignored, backticks and parentheticals are stripped from the list" \
'glossary: docs/a.md:2: "autopilot" is on the _Avoid_ list of Ship; use Ship if the word names it
glossary: docs/a.md:3: "raw gh call" is on the _Avoid_ list of Verdict; use Verdict if the word names it
glossary: docs/a.md:4: "gate output" is on the _Avoid_ list of Verdict; use Verdict if the word names it' "$(run "$d" main)"

d=$(mkrepo whole-word)
printf 'line one\nreports and resulting and pipelines\n' > "$d/docs/a.md"; git_ commit -q -am head
check "a word inside a longer word is not a hit" "" "$(run "$d" main)"

# The new-file line number follows the hunk header, not the position in the diff.
d=$(mkrepo hunk-lines)
printf 'a\nb\nc\nd\ne\n' > "$d/docs/b.md"; git_ add -A; git_ commit -q -m more; git_ branch -q -f main HEAD
printf 'a\nb\nc\nd\ne\nresult\nfine\nresult\n' > "$d/docs/b.md"; git_ commit -q -am head
check "each added line is numbered in the new file" \
'glossary: docs/b.md:6: "result" is on the _Avoid_ list of Verdict; use Verdict if the word names it
glossary: docs/b.md:8: "result" is on the _Avoid_ list of Verdict; use Verdict if the word names it' "$(run "$d" main)"

d=$(mkrepo clean)
printf 'line one\nnothing avoided here\n' > "$d/docs/a.md"; git_ commit -q -am head
check "a clean diff prints nothing" "" "$(run "$d" main)"
check_rc "a clean diff exits 0" 0 "$(rc_of "$d" main)"

d=$(mkrepo removed)
printf 'pipeline\n' > "$d/docs/c.md"; git_ add -A; git_ commit -q -m more; git_ branch -q -f main HEAD
printf 'fine\n' > "$d/docs/c.md"; git_ commit -q -am head
check "a removed line is not a hit" "" "$(run "$d" main)"

d=$(mkrepo changelog)
printf '# Changelog\n\n- the pipeline\n' > "$d/docs/CHANGELOG.md"; printf 'pipeline\n' > "$d/CHANGELOG.md"
printf 'plain pipeline\n' > "$d/docs/n.txt"
git_ add -A; git_ commit -q -m head
check "CHANGELOG.md files and non-markdown files are not read" "" "$(run "$d" main)"

d=$(mkrepo derived-copy)
mkdir -p "$d/skills/x" "$d/.claude/skills/x"
printf 'ship the pipeline\n' > "$d/skills/x/SKILL.md"; printf 'ship the pipeline\n' > "$d/.claude/skills/x/SKILL.md"
git_ add -A; git_ commit -q -m head
check "a hit in a derived copy under .claude/ is not repeated" \
  'glossary: skills/x/SKILL.md:1: "pipeline" is on the _Avoid_ list of Ship; use Ship if the word names it' "$(run "$d" main)"

d=$(mkrepo glossary-itself)
printf '\n**Other**:\nx\n_Avoid_: pipeline\n' >> "$d/GLOSSARY.md"; git_ commit -q -am head
check "GLOSSARY.md itself is not read" "" "$(run "$d" main)"

d=$(mkrepo bad-base)
rc=$(rc_of "$d" no-such-ref)
check_rc "a base that is not a commit is tooling" 2 "$rc"
check "tooling names the base on stderr" "glossary-warn: base no-such-ref is not a commit" "$(cd "$d" && bash "$script" no-such-ref 2>&1 >/dev/null | head -n 1)"

d=$(mkrepo no-origin)
check_rc "no base and no origin/HEAD is tooling" 2 "$(rc_of "$d")"

d=$(mkrepo no-glossary)
git_ rm -q GLOSSARY.md; git_ commit -q -m head
check_rc "a repo with no GLOSSARY.md is tooling" 2 "$(rc_of "$d" main)"

finish
