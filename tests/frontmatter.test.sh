#!/usr/bin/env bash
# scripts/frontmatter-check.sh: the frontmatter of every skill this repo writes.
# Each case builds a tree at the real relative paths under a fresh root, so a
# fixture differs from a clean tree only in the defect under test: the key
# allowlist, both sides of the 1,024-character boundary, the "Use when" clause
# with and without `disable-model-invocation: true`, the scalar forms a
# description takes, and the path where the input cannot be read.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'chmod -R u+rwx "$fixture"; rm -rf "$fixture"' EXIT

# <case>: a root whose lock lists `clean` as a skill this repo writes and
# `vendored` as one it installs; prints its path.
tree() {
  local d="$fixture/$1"; rm -rf "$d"
  mkdir -p "$d/skills/clean" || return 1
  printf '%s\n' '{"version": 1, "skills": {"clean": {"source": "."}, "vendored": {"source": "o/r", "ref": "x"}}}' \
    > "$d/skills-lock.json"
  cat > "$d/skills/clean/SKILL.md" <<'MD'
---
name: clean
description: Do the clean thing. Use when the user wants it clean.
argument-hint: "[topic]"
metadata:
  version: 0.1.0
  composes: o/r#x:other
---

body: not a key
MD
  printf '%s' "$d"
}
# <root> <name> <frontmatter line>...: one more skill this repo writes.
skill() {
  local d=$1 n=$2; shift 2
  mkdir -p "$d/skills/$n" || return 1
  jq --arg n "$n" '.skills[$n] = {source: "."}' "$d/skills-lock.json" > "$d/l" && mv "$d/l" "$d/skills-lock.json"
  { echo ---; printf '%s\n' "$@"; echo ---; } > "$d/skills/$n/SKILL.md"
}
rc_of()  { bash scripts/frontmatter-check.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { bash scripts/frontmatter-check.sh "$1" 2>/dev/null; }
# <n>: a description of exactly n characters carrying the clause.
desc() { local s="Use when"; while [ "${#s}" -lt "$1" ]; do s="${s}x"; done; printf '%s' "$s"; }

# The real tree, so a skill this repo writes that breaks the rules fails a case
# here rather than leaving every synthetic fixture green.
check_rc "the current tree passes" 0 "$(rc_of .)"

d=$(tree clean)
check_rc "a clean tree passes" 0 "$(rc_of "$d")"
check "a clean tree prints nothing" '' "$(out_of "$d")"

d=$(tree forms)
skill "$d" folded name: folded 'description: >-' '  Folded across lines.' '  Use when it folds.'
skill "$d" quoted name: quoted 'description: "Quoted: with a colon. Use when quoted."'
skill "$d" manual name: manual 'description: "Run by hand only."' 'disable-model-invocation: true'
check_rc "folded, quoted and manual-only descriptions pass" 0 "$(rc_of "$d")"

# A YAML comment after an unquoted value is not part of it; inside quotes it is.
d=$(tree comments)
skill "$d" manual name: manual 'description: Run by hand only. # no clause' 'disable-model-invocation: true # manual-only'
skill "$d" hashed name: hashed 'description: "Use when # is in quotes."'
check_rc "a comment after an unquoted value is dropped" 0 "$(rc_of "$d")"

d=$(tree unknown-key)
skill "$d" extra name: extra 'description: Use when extra.' 'allowed-tools: Bash'
check_rc "a key outside the allowlist fails" 1 "$(rc_of "$d")"
check "the message names the file and the key" \
  "skills/extra/SKILL.md: frontmatter key allowed-tools is not allowed" "$(out_of "$d")"

# A key the allowlist names, with a suffix, is another key.
d=$(tree partial-key)
skill "$d" plural name: plural 'description: Use when plural.' 'descriptions: x'
check "a longer key sharing an allowed prefix fails" \
  "skills/plural/SKILL.md: frontmatter key descriptions is not allowed" "$(out_of "$d")"

d=$(tree at-1024)
skill "$d" long name: long "description: $(desc 1024)"
check_rc "a 1,024-character description passes" 0 "$(rc_of "$d")"

d=$(tree over-1024)
skill "$d" long name: long "description: $(desc 1025)"
check_rc "a 1,025-character description fails" 1 "$(rc_of "$d")"
check "the message names the length" \
  "skills/long/SKILL.md: description is 1025 characters, over 1024" "$(out_of "$d")"

# A folded description is counted as the agent reads it, its lines joined.
d=$(tree folded-over)
skill "$d" long name: long 'description: >-' "  $(desc 1000)" "  $(desc 24)"
check "a folded description is counted joined" \
  "skills/long/SKILL.md: description is 1025 characters, over 1024" "$(out_of "$d")"

d=$(tree no-use-when)
skill "$d" silent name: silent 'description: Does a thing.'
check_rc "a model-invoked skill without Use when fails" 1 "$(rc_of "$d")"
check "the message names the clause" \
  'skills/silent/SKILL.md: description has no "Use when" clause' "$(out_of "$d")"

d=$(tree invocation-false)
skill "$d" silent name: silent 'description: Does a thing.' 'disable-model-invocation: false'
check_rc "disable-model-invocation: false fails" 1 "$(rc_of "$d")"
check "disable-model-invocation: false still needs the clause" \
  'skills/silent/SKILL.md: description has no "Use when" clause' "$(out_of "$d")"

# Only a key at column 0 is a frontmatter key: metadata's children and the body
# below the closing fence are not.
d=$(tree indented)
skill "$d" nested name: nested 'description: Use when nested.' 'metadata:' '  anything: goes'
check_rc "an indented key under metadata passes" 0 "$(rc_of "$d")"

d=$(tree vendored)
mkdir -p "$d/skills/vendored" && printf -- '---\nname: vendored\nallowed-tools: Bash\n---\n' > "$d/skills/vendored/SKILL.md"
check_rc "a skill another repo writes is not checked" 0 "$(rc_of "$d")"

d=$(tree unclosed)
printf -- '---\nname: clean\ndescription: Use when unclosed.\n' > "$d/skills/clean/SKILL.md"
check_rc "a frontmatter with no closing fence fails" 1 "$(rc_of "$d")"
check "the message names the closing fence" \
  "skills/clean/SKILL.md: frontmatter has no closing ---" "$(out_of "$d")"

d=$(tree unopened)
printf 'name: clean\ndescription: Use when unopened.\n' > "$d/skills/clean/SKILL.md"
check_rc "a SKILL.md with no opening fence fails" 1 "$(rc_of "$d")"
check "the message names the opening fence" \
  "skills/clean/SKILL.md: frontmatter has no opening ---" "$(out_of "$d")"

check_rc "a missing root exits 2" 2 "$(rc_of "$fixture/absent")"

d=$(tree no-lock); rm "$d/skills-lock.json"
check_rc "a root with no lock exits 2" 2 "$(rc_of "$d")"

d=$(tree no-skill-file); rm "$d/skills/clean/SKILL.md"
check_rc "a listed skill with no SKILL.md exits 2" 2 "$(rc_of "$d")"

if [ "$(id -u)" != 0 ]; then
  d=$(tree unreadable-skill); chmod 000 "$d/skills/clean/SKILL.md"
  check_rc "an unreadable SKILL.md exits 2" 2 "$(rc_of "$d")"
  d=$(tree unreadable-root); chmod 000 "$d"
  check_rc "an unreadable root exits 2" 2 "$(rc_of "$d")"
else
  skipped "an unreadable SKILL.md and an unreadable root: root reads any file"
fi

finish
