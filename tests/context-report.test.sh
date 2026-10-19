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

rm "$d/skills-lock.json"
bash "$script" "$d" >/dev/null 2>&1; rc=$?
check_rc "a missing lock is tooling" 2 "$rc"
printf 'not json' > "$d/skills-lock.json"
bash "$script" "$d" >/dev/null 2>&1; rc=$?
check_rc "an unreadable lock is tooling" 2 "$rc"

finish
