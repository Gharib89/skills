#!/usr/bin/env bash
# ship_missing_skill_reasons: the skills ship composes, checked against a
# checkout's .claude/skills/. A pure filesystem read over a fixture tree; no
# call in this file reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

root=$(mktemp -d) || exit 2
trap 'rm -rf "$root"' EXIT
install() { mkdir -p "$root/.claude/skills/$1" && touch "$root/.claude/skills/$1/SKILL.md"; }

composes='mattpocock/skills:tdd upstash/context7:find-docs'
reasons() { ship_missing_skill_reasons "$root" "$composes"; }

install tdd; install find-docs
check "every composed skill present" '' "$(reasons)"

rm -rf "$root/.claude/skills/tdd"
check "one absent skill names its install line" \
  'skill missing: tdd; run npx skills add mattpocock/skills --skill tdd --agent claude-code -y' \
  "$(reasons)"

# One report, not one stop per skill: preflight collects these alongside its
# other reasons, so a human fixes every missing skill in one pass.
rm -rf "$root/.claude/skills/find-docs"
check "two absent skills give two reasons, in frontmatter order" \
  'skill missing: tdd; run npx skills add mattpocock/skills --skill tdd --agent claude-code -y
skill missing: find-docs; run npx skills add upstash/context7 --skill find-docs --agent claude-code -y' \
  "$(reasons)"

# A directory without SKILL.md is not an installed skill: `skills add` writes
# the file, so its absence is a half-installed copy the Skill tool cannot load.
mkdir -p "$root/.claude/skills/tdd"
check "a skill directory without SKILL.md is absent" \
  'skill missing: tdd; run npx skills add mattpocock/skills --skill tdd --agent claude-code -y
skill missing: find-docs; run npx skills add upstash/context7 --skill find-docs --agent claude-code -y' \
  "$(reasons)"

check "an empty composes line checks nothing" '' "$(ship_missing_skill_reasons "$root" '')"

# The split is on spaces only: an entry is never expanded against the working
# directory, whatever it happens to contain.
check "a glob character stays literal" \
  'skill missing: *; run npx skills add o/r --skill * --agent claude-code -y' \
  "$(cd / && ship_missing_skill_reasons "$root" 'o/r:*')"

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
