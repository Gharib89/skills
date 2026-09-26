#!/usr/bin/env bash
# ship_missing_skill_reasons: the skills ship composes, checked against a
# checkout's .claude/skills/ and the refs its skills-lock.json records. A pure
# filesystem read over a fixture tree; no call in this file reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

root=$(mktemp -d) || exit 2
trap 'rm -rf "$root"' EXIT
install() { mkdir -p "$root/.claude/skills/$1" && touch "$root/.claude/skills/$1/SKILL.md"; }
# <skill> <ref|"">...: the consumer's skills-lock.json, each skill at that ref.
lock() {
  local out='{}'
  while [ $# -gt 0 ]; do
    out=$(jq --arg k "$1" --arg r "$2" '.[$k] = ({source: "o/r"} + (if $r == "" then {} else {ref: $r} end))' <<<"$out")
    shift 2
  done
  jq '{version: 1, skills: .}' <<<"$out" > "$root/skills-lock.json"
}

# Pinned refs: a composed skill installs at the commit the source repo tested.
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
composes="mattpocock/skills#$A:tdd upstash/context7#$B:find-docs"
reasons() { ship_missing_skill_reasons "$root" "$composes"; }

install tdd; install find-docs; lock tdd "$A" find-docs "$B"
check "every composed skill present at its pin" '' "$(reasons)"

# The lock's ref is what the copy was installed at: a copy from another commit,
# or from upstream HEAD (no ref), is not the one the source repo tested.
lock tdd "$B" find-docs "$B"
check "a copy the lock records at another ref is off its pin" \
  "skill off pin: tdd at $B, pinned $A; run npx skills add mattpocock/skills#$A --skill tdd --agent claude-code -y" \
  "$(reasons)"
lock tdd "" find-docs "$B"
check "a copy the lock records with no ref is off its pin" \
  "skill off pin: tdd at none, pinned $A; run npx skills add mattpocock/skills#$A --skill tdd --agent claude-code -y" \
  "$(reasons)"
lock tdd "" find-docs "$B"; jq '.skills.tdd.ref = ""' "$root/skills-lock.json" > "$root/l" && mv "$root/l" "$root/skills-lock.json"
check "an empty ref reads as none" \
  "skill off pin: tdd at none, pinned $A; run npx skills add mattpocock/skills#$A --skill tdd --agent claude-code -y" \
  "$(reasons)"

# The CLI reads a lock it cannot parse as empty and rewrites it holding only the
# new entry, so an install line printed here would erase every other entry.
for bad in '{"skills":' '{"skills":{}} {"skills":{}}' '[]'; do
  printf '%s' "$bad" > "$root/skills-lock.json"
  check "a lock that is not one JSON object is refused, with no install line: $bad" \
    "skills lock unreadable: skills-lock.json; repair it, then re-run preflight" \
    "$(reasons)"
done
rm -f "$root/skills-lock.json"
check "with no lock every present copy is off its pin" \
  "skill off pin: tdd at none, pinned $A; run npx skills add mattpocock/skills#$A --skill tdd --agent claude-code -y
skill off pin: find-docs at none, pinned $B; run npx skills add upstash/context7#$B --skill find-docs --agent claude-code -y" \
  "$(reasons)"
lock tdd "$A" find-docs "$B"

rm -rf "$root/.claude/skills/tdd"
check "one absent skill names its install line" \
  "skill missing: tdd; run npx skills add mattpocock/skills#$A --skill tdd --agent claude-code -y" \
  "$(reasons)"

# One report, not one stop per skill: preflight collects these alongside its
# other reasons, so a human fixes every missing skill in one pass.
rm -rf "$root/.claude/skills/find-docs"
check "two absent skills give two reasons, in frontmatter order" \
  "skill missing: tdd; run npx skills add mattpocock/skills#$A --skill tdd --agent claude-code -y
skill missing: find-docs; run npx skills add upstash/context7#$B --skill find-docs --agent claude-code -y" \
  "$(reasons)"

# A directory without SKILL.md is not an installed skill: `skills add` writes
# the file, so its absence is a half-installed copy the Skill tool cannot load.
mkdir -p "$root/.claude/skills/tdd"
check "a skill directory without SKILL.md is absent" \
  "skill missing: tdd; run npx skills add mattpocock/skills#$A --skill tdd --agent claude-code -y
skill missing: find-docs; run npx skills add upstash/context7#$B --skill find-docs --agent claude-code -y" \
  "$(reasons)"

check "an empty composes line checks nothing" '' "$(ship_missing_skill_reasons "$root" '')"

# The split is on spaces only: an entry is never expanded against the working
# directory, whatever it happens to contain.
check "a glob character stays literal" \
  "skill missing: *; run npx skills add o/r#$A --skill * --agent claude-code -y" \
  "$(cd / && ship_missing_skill_reasons "$root" "o/r#$A:*")"

# A pin that is not a 40-hex sha installs whatever the upstream holds today, so
# it is refused whether or not the skill is present: the installed copy proves
# nothing about which commit it came from.
install tdd; install find-docs
for bad in "mattpocock/skills:tdd" "mattpocock/skills#main:tdd" "mattpocock/skills#${A:0:7}:tdd" \
           "mattpocock/skills#${A}0:tdd" "mattpocock/skills#$(printf 'A%.0s' {1..40}):tdd" "skills#$A:tdd"; do
  check "a malformed pin is refused: $bad" \
    "composes pin invalid: $bad; want <owner>/<repo>#<40-hex sha>:<skill>" \
    "$(ship_missing_skill_reasons "$root" "$bad upstash/context7#$B:find-docs")"
done

# ship_frontmatter reads the line preflight passes in. A body line that looks
# like the key is past the closing `---` and must not be read as one.
fm=$(mktemp) || exit 2
trap 'rm -rf "$root"; rm -f "$fm"' EXIT
cat > "$fm" <<'MD'
---
name: ship
metadata:
  version: 3.5.0
  composes: mattpocock/skills:tdd upstash/context7:find-docs
---

  composes: not-this-one
MD

check "a single-token value"          '3.5.0' "$(ship_frontmatter "$fm" version)"
check "a space-separated value whole" 'mattpocock/skills:tdd upstash/context7:find-docs' \
  "$(ship_frontmatter "$fm" composes)"
check "a key the frontmatter lacks"   ''      "$(ship_frontmatter "$fm" profile-schema)"

finish
