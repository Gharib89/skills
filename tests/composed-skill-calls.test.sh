#!/usr/bin/env bash
# A skill ship composes that calls another skill through the Skill tool needs
# that skill installed beside it, and preflight installs only what `composes`
# names. So every such call in a composed skill's installed copy names a skill
# on ship's `composes` line, or the call fails in a consumer repo (#609).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

# <skills-dir> <composed names, one per line>: one line per skill a composed
# skill's Markdown calls through the Skill tool that is not composed. A call is
# every quoted or backticked name in the clause after "Skill tool", read with
# lines joined, since a call can wrap or name two skills ("twice, for "a" and
# "b"").
uncomposed() {
  local s f called
  for s in $2; do
    while IFS= read -r -d '' f; do
      tr '\n' ' ' < "$f" | tr -s ' ' | grep -oE 'Skill tool[^.;]*' | grep -oE '["`][a-z][a-z0-9-]*["`]' | tr -d '"`' |
        while read -r called; do
          grep -qxF "$called" <<<"$2" || echo "$s calls $called, which ship does not compose"
        done
    done < <(find "$1/$s" -name '*.md' -print0)
  done | sort -u
}

composed=$(ship_frontmatter skills/ship/SKILL.md composes | tr ' ' '\n' | sed 's/.*://')
check "every Skill-tool call in a composed skill names a composed skill" '' "$(uncomposed .claude/skills "$composed")"

fx=$(mktemp -d); trap 'rm -rf "$fx"' EXIT
mkdir -p "$fx/a/ref" "$fx/ok"
# <file> <text>: a composed skill `a`'s Markdown, composed with `ok` beside it.
calls() { rm -f "$fx"/a/*.md "$fx"/a/ref/*.md; printf '%s\n' "$2" > "$fx/a/$1"; uncomposed "$fx" "a
ok"; }
check "a double-quoted call" "a calls new, which ship does not compose" "$(calls SKILL.md 'call the Skill tool with "new" for it.')"
check "a backticked call" "a calls new, which ship does not compose" "$(calls SKILL.md 'Call the Skill tool with `new` for the style.')"
check "a call wrapped across lines" "a calls new, which ship does not compose" "$(calls SKILL.md 'call the Skill
tool with "new".')"
check "two skills in one call" "a calls new, which ship does not compose" "$(calls SKILL.md 'Call the Skill tool twice, for "ok" and "new".')"
check "a call in a referenced file" "a calls new, which ship does not compose" "$(calls ref/STEPS.md 'call the Skill tool with "new".')"
check "a composed callee" '' "$(calls SKILL.md 'call the Skill tool with "ok".')"
check "a name in the next sentence is no call" '' "$(calls SKILL.md 'A command the Skill tool cannot run. Use `new` instead.')"

finish
