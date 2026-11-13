#!/usr/bin/env bash
# scripts/skills-cli-check.sh: the lock is in the pinned CLI's format with
# every hash filled, and every `npx skills` line this repo writes names the
# pinned CLI version. Each case builds a root holding only the files under
# test, so a fixture differs from a passing tree only in the fault under test.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
H=$(printf 'a%.0s' {1..64})

# <case> <version> <hash> [<file> <text>]...: a root holding a lock of one
# GitHub entry, tdd, at that version and hash, plus each file given.
tree() {
  local d="$fixture/$1"; rm -rf "$d"; mkdir -p "$d" || return 1
  jq -n --argjson v "$2" --arg h "$3" \
    '{version: $v, skills: {tdd: {source: "o/r", ref: "abc", sourceType: "github", computedHash: $h}}}' > "$d/skills-lock.json"
  shift 3
  while [ $# -gt 0 ]; do
    mkdir -p "$(dirname "$d/$1")" && printf '%s\n' "$2" > "$d/$1"
    shift 2
  done
  printf '%s' "$d"
}
rc_of()  { bash scripts/skills-cli-check.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { bash scripts/skills-cli-check.sh "$1" 2>/dev/null; }

check_rc "the current tree passes" 0 "$(rc_of .)"

good='npx skills@1.8.1 add o/r#abc --skill tdd --agent claude-code -y'
check_rc "a version 2 lock with hashes and a pinned line passes" 0 \
  "$(rc_of "$(tree ok 2 "$H" CLAUDE.md "$good")")"

d=$(tree v1 1 "$H")
check_rc "a version 1 lock fails" 1 "$(rc_of "$d")"
check "and names the fix" \
  "skills-lock.json is version 1, not 2: refresh it with npx skills@1.8.1, then re-add each GitHub entry at its locked ref" \
  "$(out_of "$d")"

d=$(tree blank 2 "")
check_rc "an empty computedHash fails" 1 "$(rc_of "$d")"
check "and names the entry and its re-add line" \
  "skills-lock.json: tdd has no computedHash; re-add it at its locked ref: npx skills@1.8.1 add o/r#abc --skill tdd --agent claude-code -y" \
  "$(out_of "$d")"

d=$(tree bare 2 "$H" skills/x/SKILL.md 'Run `npx skills add o/r --skill x --agent claude-code -y` first.')
check_rc "an unversioned invocation fails" 1 "$(rc_of "$d")"
check "and names the file and line" \
  "skills/x/SKILL.md:1: unversioned npx skills, write npx skills@1.8.1" \
  "$(out_of "$d")"

d=$(tree npxy 2 "$H" scripts/run.sh '(npx -y skills add "$src" --skill ship)')
check_rc "an unversioned npx -y invocation fails too" 1 "$(rc_of "$d")"
check "and names the file and line" \
  "scripts/run.sh:1: unversioned npx skills, write npx skills@1.8.1" \
  "$(out_of "$d")"

d=$(tree other 2 "$H" CLAUDE.md 'npx skills@latest add . --skill ship')
check_rc "another version fails" 1 "$(rc_of "$d")"
check "and names the version and the pin" \
  "CLAUDE.md:1: npx skills@latest, not the pinned npx skills@1.8.1" \
  "$(out_of "$d")"

# The release configs run the refresh line on main, so they are read too.
d=$(tree release 2 "$H" .release/ship.toml 'npx -y skills@1.7.0 add . --skill ship --agent claude-code -y')
check_rc "a release config on another version fails" 1 "$(rc_of "$d")"
check "and names the file, the version and the pin" \
  ".release/ship.toml:1: npx skills@1.7.0, not the pinned npx skills@1.8.1" \
  "$(out_of "$d")"

# A file the search cannot read is a failed read, never a clean pass.
d=$(tree unreadable 2 "$H" docs/x.md 'npx skills@1.8.1 add o/r --skill x')
chmod 000 "$d/docs/x.md"
check_rc "a search that cannot read a file is tooling" 2 "$(rc_of "$d")"
chmod 644 "$d/docs/x.md"

# A changelog records the lines as they were; it is history, not an invocation.
check_rc "a changelog line is not read" 0 \
  "$(rc_of "$(tree log 2 "$H" skills/x/CHANGELOG.md '- ran `npx skills add .`')")"

finish
