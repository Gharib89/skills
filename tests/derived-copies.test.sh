#!/usr/bin/env bash
# scripts/derived-copies-check.sh: the lock's `source: "."` entries are the set
# of skills this repo writes, and every other place that names the set agrees
# with it. Each case builds an agreeing tree at the real relative paths under a
# fresh root and breaks one place, so a failure names the drift under test.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <case>: a tree writing `ship` and `setup-skills`, with `tdd` vendored. Each
# file is the least the check and its two sub-checks read.
tree() {
  local d="$fixture/$1" s; rm -rf "$d"
  mkdir -p "$d/.github/workflows" "$d/.release" "$d/.claude/skills/tdd" || return 1
  jq -n '{version: 1, skills: {
    ship: {source: ".", sourceType: "local"},
    "setup-skills": {source: ".", sourceType: "local"},
    tdd: {source: "o/r", ref: "'"$(printf 'a%.0s' {1..40})"'", sourceType: "github"}}}' > "$d/skills-lock.json"
  mkdir -p "$d/skills/ship" "$d/skills/setup-skills"
  printf -- '---\nname: ship\nmetadata:\n  profile-schema: 3\n---\n\n# ship\n' > "$d/skills/ship/SKILL.md"
  printf -- '---\nname: setup-skills\n---\n\n# setup-skills\n' > "$d/skills/setup-skills/SKILL.md"
  printf 'Schema: 3\n' > "$d/skills/setup-skills/ship-profile.md"
  printf '## Schema 3\n' > "$d/skills/setup-skills/profile-schema.md"
  for s in ship setup-skills; do
    cp -R "$d/skills/$s" "$d/.claude/skills/$s"
    printf 'commit_message = "chore(release): %s v{version}"\n' "$s" > "$d/.release/$s.toml"
  done
  cat > "$d/.github/workflows/semantic-release.yml" <<'EOF'
jobs:
  release:
    if: >-
      ${{ !(github.event.head_commit.author.name == 'github-actions[bot]'
      && (startsWith(github.event.head_commit.message, 'chore(release): ship v')
      || startsWith(github.event.head_commit.message, 'chore(release): setup-skills v'))) }}
    env:
      SKILLS: ship setup-skills
EOF
  printf '%s' "$d"
}
rc_of()  { bash scripts/derived-copies-check.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { bash scripts/derived-copies-check.sh "$1" 2>/dev/null; }
wf=.github/workflows/semantic-release.yml

check_rc "the current tree agrees" 0 "$(rc_of .)"
check_rc "a tree whose places agree with the lock passes, its vendored entry ignored" 0 "$(rc_of "$(tree agree)")"

d=$(tree nocopy); rm -rf "$d/.claude/skills/setup-skills"
check "a source-. skill with no derived copy fails" \
  "missing derived copy: .claude/skills/setup-skills" "$(out_of "$d")"

d=$(tree list); sed -i.bak 's/SKILLS: ship setup-skills/SKILLS: ship/' "$d/$wf"
check "a workflow SKILLS list missing a skill fails" \
  "$wf SKILLS names ship, the lock's set is setup-skills ship" "$(out_of "$d")"

d=$(tree cond); sed -i.bak "/setup-skills v'/d; s/ship v')\$/ship v'))) }}/" "$d/$wf"
check "a release condition missing a skill fails" \
  "$wf release-commit conditions name ship, the lock's set is setup-skills ship" "$(out_of "$d")"

# A subject quoted in a comment or a SKILLS line under a comment marker is not
# the condition or the list the release job reads.
d=$(tree decoy); sed -i.bak "/setup-skills v'/d; s/ship v')\$/ship v'))) }}/" "$d/$wf"
printf "      # 'chore(release): setup-skills v'\n      # SKILLS: ship setup-skills\n" >> "$d/$wf"
sed -i.bak 's/SKILLS: ship setup-skills$/SKILLS: ship/' "$d/$wf"
check "a decoy subject or list in a comment does not satisfy the check" \
  "$wf SKILLS names ship, the lock's set is setup-skills ship
$wf release-commit conditions name ship, the lock's set is setup-skills ship" "$(out_of "$d")"

d=$(tree norelease); rm "$d/.release/setup-skills.toml"
check "a source-. skill with no release configuration fails" \
  "missing release configuration: .release/setup-skills.toml" "$(out_of "$d")"

# Its derived copy goes too, so the only difference left is the missing source.
d=$(tree nosource); rm -rf "$d/skills/setup-skills" "$d/.claude/skills/setup-skills"
check "a source-. lock entry with no skills/<name>/ fails on stdout" \
  "missing source: skills/setup-skills" "$(out_of "$d")"

d=$(tree unlocked); mkdir -p "$d/skills/new" "$d/.claude/skills/new"
check "a skills/<name>/ the lock does not record as source . fails" \
  "skills/new is not a source \".\" entry in skills-lock.json; add --skill new to the refresh line and run it" "$(out_of "$d")"

# A workflow the check cannot read is tooling, not a list that disagrees. Root
# reads a mode-000 file, so the case only runs where the mode bits bind.
if [ "$(id -u)" -ne 0 ]; then
  d=$(tree unreadable); chmod 000 "$d/$wf"
  check_rc "an unreadable release workflow is tooling" 2 "$(rc_of "$d")"
  chmod 644 "$d/$wf"
else
  skipped "an unreadable release workflow is tooling"
fi

d="$fixture/nolock"; mkdir -p "$d"
check_rc "a tree with no lock is tooling" 2 "$(rc_of "$d")"

finish
