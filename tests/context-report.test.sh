#!/usr/bin/env bash
# scripts/context-report.sh: one line per always-on source of a checkout, in
# characters, then a total. A report never fails the run, so every case but the
# tooling one asserts exit 0 and the printed lines.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
script=$PWD/scripts/context-report.sh

# A checkout with a 10-character CLAUDE.md, no AGENTS.md, an owned skill whose
# description is a folded `>-` scalar (two lines joining to "alpha beta", 10
# characters), an owned one-line description (8 characters, one of them
# multibyte), and a vendored skill that must stay out of the report.
d=$fixture/repo
mkdir -p "$d/skills/folded" "$d/skills/plain" "$d/skills/vendored"
printf '0123456789' > "$d/CLAUDE.md"
printf -- '---\nname: folded\ndescription: >-\n  alpha\n  beta\nmetadata:\n  version: 0.1.0\n---\nbody\n' > "$d/skills/folded/SKILL.md"
printf -- '---\nname: plain\ndescription: "caf\xc3\xa9 one"\n---\nbody\n' > "$d/skills/plain/SKILL.md"
printf -- '---\nname: vendored\ndescription: should never be counted\n---\n' > "$d/skills/vendored/SKILL.md"
cat > "$d/skills-lock.json" <<'L'
{"version":1,"skills":{
  "folded":{"source":"."},
  "plain":{"source":"."},
  "vendored":{"source":"someone/else","ref":"abc"}}}
L

out=$(cd "$d" && bash "$script" 2>"$fixture/err"); rc=$?
check_rc "a report exits 0" 0 "$rc"
check "one line per source: an absent AGENTS.md, a folded description in full, no vendored skill, a total" \
'CLAUDE.md: 10 chars
AGENTS.md: absent
skills/folded: 10 chars
skills/plain: 8 chars
total: 28 chars' "$out"

# Characters, not bytes, under a locale that counts bytes.
out=$(cd "$d" && LC_ALL=C bash "$script" 2>/dev/null)
check "a multibyte character counts once under LC_ALL=C" "skills/plain: 8 chars" "$(grep '^skills/plain' <<<"$out")"

# The root is an argument, and a checkout with neither root file still reports.
out=$(cd "$fixture" && bash "$script" repo 2>/dev/null)
check "the root argument is read" "CLAUDE.md: 10 chars" "$(head -1 <<<"$out")"

mkdir -p "$fixture/bare"
printf '{"version":1,"skills":{}}\n' > "$fixture/bare/skills-lock.json"
out=$(bash "$script" "$fixture/bare" 2>/dev/null); rc=$?
check_rc "absent root files are no error" 0 "$rc"
check "both absent, total zero" 'CLAUDE.md: absent
AGENTS.md: absent
total: 0 chars' "$out"

# The description reader against the shapes frontmatter-check.sh reads: each
# skill's description below is one such shape, its expected count in the block.
a=$fixture/adv
mkdir -p "$a"
printf '{"version":1,"skills":{"single":{"source":"."},"literal":{"source":"."},"comment":{"source":"."},"trailing":{"source":"."},"blockquote":{"source":"."},"none":{"source":"."},"decoy":{"source":"."},"unclosed":{"source":"."}}}\n' > "$a/skills-lock.json"
skill() { mkdir -p "$a/skills/$1"; printf -- '---\nname: %s\n%b---\nbody\n' "$1" "$2" > "$a/skills/$1/SKILL.md"; }
skill single "description: 'single one'\n"
skill literal "description: |\n  one\n  two\n"
skill comment "description: plain text # note\n"
skill trailing "description: abc   \n"
skill blockquote "description: >-\n  say \"hi\"\n  there\n"
skill none "metadata:\n  version: 0.1.0\n"
skill decoy "descriptions: zzzzzz\ndescription: ab\n"
skill unclosed "description: \"never closed\n"
out=$(bash "$script" "$a" 2>/dev/null); rc=$?
check_rc "every shape reports" 0 "$rc"
check "single quotes, a literal block, a trailing comment and blanks, a quote inside a block, no description, a decoy key, an unclosed quote" \
'CLAUDE.md: absent
AGENTS.md: absent
skills/single: 10 chars
skills/literal: 7 chars
skills/comment: 10 chars
skills/trailing: 3 chars
skills/blockquote: 14 chars
skills/none: 0 chars
skills/decoy: 2 chars
skills/unclosed: 13 chars
total: 59 chars' "$out"

# A counting tool that fails is tooling, never a zero.
mkdir -p "$fixture/failbin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fixture/failbin/tr"; chmod +x "$fixture/failbin/tr"
out=$(PATH="$fixture/failbin:$PATH" bash "$script" "$a" 2>"$fixture/err"); rc=$?
check_rc "a failing tr is tooling" 2 "$rc"
check "a failing tr names the source it could not count" \
  "context-report: cannot count skills/single" "$(cat "$fixture/err")"
check "a failing tr prints no count" "0" "$(grep -c 'chars' <<<"$out")"

rm "$a/skills/none/SKILL.md"
bash "$script" "$a" >/dev/null 2>&1; rc=$?
check_rc "an owned skill without a SKILL.md is tooling" 2 "$rc"

rm "$d/skills-lock.json"
bash "$script" "$d" >/dev/null 2>&1; rc=$?
check_rc "a missing lock is tooling" 2 "$rc"
printf 'not json' > "$d/skills-lock.json"
bash "$script" "$d" >/dev/null 2>&1; rc=$?
check_rc "an unreadable lock is tooling" 2 "$rc"

finish
