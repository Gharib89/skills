#!/usr/bin/env bash
# scripts/pin-check.sh: every pinned ref a skill states agrees with the ref this
# repo's lock installed. Each case builds a tree at the real relative paths
# under a fresh root, so a fixture differs from an agreeing tree only in the
# drift under test.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
A=$(printf 'a%.0s' {1..40}); B=$(printf 'b%.0s' {1..40})

# <composes>: a SKILL.md whose frontmatter carries that line, then a body.
skill_file() { printf -- '---\nname: x\nmetadata:\n  version: 1.0.0\n  composes: %s\n---\n\n# x\n' "$1"; }
# <skill> <source> <ref|"">...: a lock holding those entries.
lock_file() {
  local out='{}'
  while [ $# -gt 0 ]; do
    out=$(jq --arg k "$1" --arg s "$2" --arg r "$3" \
      '.[$k] = ({source: $s, sourceType: "github"} + (if $r == "" then {} else {ref: $r} end))' <<<"$out")
    shift 3
  done
  jq '{version: 1, skills: .}' <<<"$out"
}
# <case> <ship> <setup-skills> <lock>: a root holding the three files.
tree() {
  local d="$fixture/$1"; rm -rf "$d"
  mkdir -p "$d/skills/ship" "$d/skills/setup-skills" || return 1
  printf '%s\n' "$2" > "$d/skills/ship/SKILL.md"
  printf '%s\n' "$3" > "$d/skills/setup-skills/SKILL.md"
  printf '%s\n' "$4" > "$d/skills-lock.json"
  printf '%s' "$d"
}
rc_of()  { bash scripts/pin-check.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { bash scripts/pin-check.sh "$1" 2>/dev/null; }

# The real tree, so a format change in the files it reads fails a case here
# rather than leaving every synthetic fixture green.
check_rc "the current tree agrees" 0 "$(rc_of .)"

ship="$(skill_file "o/r#$A:tdd u/c#$B:find-docs")"
setup="$(skill_file "o/r#$A:triage")"
lock="$(lock_file tdd o/r "$A" find-docs u/c "$B" triage o/r "$A")"
check_rc "every pin matches its lock ref" 0 "$(rc_of "$(tree agree "$ship" "$setup" "$lock")")"

d=$(tree moved "$ship" "$setup" "$(lock_file tdd o/r "$B" find-docs u/c "$B" triage o/r "$A")")
check_rc "a pin that differs from the lock ref fails" 1 "$(rc_of "$d")"
check "and names the skill, the pin and the lock's ref" \
  "pin drift: tdd is pinned at o/r#$A in skills/ship/SKILL.md, the lock installed o/r#$B" \
  "$(out_of "$d")"

# A lock entry the CLI wrote without `#<sha>` installed upstream HEAD, which no
# pin names.
d=$(tree unpinned "$ship" "$setup" "$(lock_file tdd o/r "" find-docs u/c "$B" triage o/r "$A")")
check "a lock entry with no ref is drift" \
  "pin drift: tdd is pinned at o/r#$A in skills/ship/SKILL.md, the lock installed o/r#none" \
  "$(out_of "$d")"

d=$(tree absent "$ship" "$setup" "$(lock_file tdd o/r "$A" find-docs u/c "$B")")
check "a composed skill absent from the lock is drift" \
  "pin drift: triage is pinned at o/r#$A in skills/setup-skills/SKILL.md, the lock installed none#none" \
  "$(out_of "$d")"

d=$(tree source "$ship" "$setup" "$(lock_file tdd fork/r "$A" find-docs u/c "$B" triage o/r "$A")")
check "the same sha from another repo is drift" \
  "pin drift: tdd is pinned at o/r#$A in skills/ship/SKILL.md, the lock installed fork/r#$A" \
  "$(out_of "$d")"

# An install line a skill prints is a pin too: setup-skills hands these to a
# human, so one left behind when the pins move installs the old commit.
body=$(printf '%s\n\n```sh\nnpx skills add o/r#%s --skill tdd --skill triage --agent claude-code -y\nnpx skills add Gharib89/skills --skill ship --agent claude-code -y\n```\n' "$setup" "$B")
d=$(tree printed "$ship" "$body" "$lock")
check "a printed install line is checked per --skill, unpinned lines skipped" \
  "pin drift: tdd is pinned at o/r#$B in skills/setup-skills/SKILL.md, the lock installed o/r#$A
pin drift: triage is pinned at o/r#$B in skills/setup-skills/SKILL.md, the lock installed o/r#$A" \
  "$(out_of "$d")"

# An unpinned composes entry is drift, named by its skill: preflight refuses the
# form, and this check must not read the source as the skill.
d=$(tree nopin "$(skill_file "o/r:tdd u/c#$B:find-docs")" "$setup" "$lock")
check "an unpinned composes entry is drift, named by its skill" \
  "pin drift: tdd is pinned at o/r#none in skills/ship/SKILL.md, the lock installed o/r#$A" \
  "$(out_of "$d")"

# A printed line that lost its sha installs upstream HEAD for a skill the lock
# pins; one for a skill the lock pins nowhere (ship itself) is not a pin.
body=$(printf '%s\n\n```sh\nnpx skills add o/r --skill tdd --agent claude-code -y\n```\n' "$setup")
d=$(tree dropped "$ship" "$body" "$lock")
check "a printed line that dropped the sha of a pinned skill is drift" \
  "pin drift: tdd is pinned at o/r#none in skills/setup-skills/SKILL.md, the lock installed o/r#$A" \
  "$(out_of "$d")"

# A body line shaped like the frontmatter key is prose, not a pin.
body=$(printf '%s\n\n  composes: o/r#%s:tdd\n' "$setup" "$B")
check_rc "a composes line below the frontmatter is not read" 0 \
  "$(rc_of "$(tree prose "$ship" "$body" "$lock")")"

d="$fixture/nolock"; mkdir -p "$d"
check_rc "a tree with no lock is tooling" 2 "$(rc_of "$d")"

finish
