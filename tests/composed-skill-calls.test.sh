#!/usr/bin/env bash
# A skill ship composes that calls another skill through the Skill tool needs
# that skill installed beside it, and preflight installs only what `composes`
# names. So every such call in a composed skill's installed copy names a skill
# on ship's `composes` line, or the call fails in a consumer repo (#609).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

composed=$(ship_frontmatter skills/ship/SKILL.md composes | tr ' ' '\n' | sed 's/.*://')
uncomposed=$(for s in $composed; do
  grep -ohE 'Skill tool with "[a-z0-9-]+"' ".claude/skills/$s/SKILL.md" | sed 's/.*"\(.*\)"/\1/' |
    while read -r called; do
      grep -qxF "$called" <<<"$composed" || echo "$s calls $called, which ship does not compose"
    done
done)
check "every Skill-tool call in a composed skill names a composed skill" '' "$uncomposed"

finish
