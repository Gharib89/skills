#!/usr/bin/env bash
# scripts/version-line-check.sh: the release run owns `metadata.version`, so a
# diff that moves one is refused before the PR opens. The seam is the script's
# CLI: a base ref and a checkout root in, an exit code and one line per offending
# file out, which is what the `version-lines` gate in scripts/local-gate.sh runs.
# Each fixture is a real checkout with a base commit and a change on top, because
# the subject is a diff against a base and nothing smaller carries one.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
git_() { git -c user.email=t@example.com -c user.name=t -C "$1" "${@:2}"; }

idiom="Read the version with \`sed -n 's/^  version: //p' SKILL.md\` at load."

# <case>: a checkout whose base commit carries two skills and one doc; prints its
# path. `base-commit` tags the base so a change committed on top is compared to
# it rather than to itself.
base_repo() {
  local d="$fixture/$1"
  rm -rf "$d"; mkdir -p "$d/skills/ship" "$d/skills/cloud-ship" "$d/skills/setup-skills" "$d/docs" || return 1
  git_ "$d" init -q || return 1
  printf -- '---\nname: ship\nmetadata:\n  version: 7.0.0\n  profile-schema: 3\n---\n\n# ship\n\n%s\n' \
    "$idiom" > "$d/skills/ship/SKILL.md"
  printf -- '---\nname: cloud-ship\nmetadata:\n  version: 1.0.2\n---\n\n# cloud-ship\n' \
    > "$d/skills/cloud-ship/SKILL.md"
  printf -- '---\nname: setup-skills\n---\n\n# setup-skills\n' \
    > "$d/skills/setup-skills/SKILL.md"
  printf -- 'A doc that happens to carry one.\n  version: 9.9.9\n' > "$d/docs/note.md"
  git_ "$d" add -Af && git_ "$d" commit -qm base && git_ "$d" tag base-commit || return 1
  printf '%s' "$d"
}
rc_of()  { bash scripts/version-line-check.sh base-commit "$1" >/dev/null 2>&1; printf '%s' "$?"; }
out_of() { bash scripts/version-line-check.sh base-commit "$1" 2>/dev/null; }

# The real tree, so a bump committed on this branch fails a case here rather than
# leaving every synthetic fixture green. `origin/HEAD` is not set by every clone,
# `actions/checkout` included, so resolve it the way `scripts/local-gate.sh` does
# and skip the case rather than report a missing ref as a version line.
if git symbolic-ref -q refs/remotes/origin/HEAD >/dev/null; then
  check_rc "this branch moves no version line" 0 \
    "$(bash scripts/version-line-check.sh "$(git merge-base origin/HEAD HEAD)" . >/dev/null 2>&1; printf '%s' "$?")"
else
  echo "skip version-line: this branch moves no version line (origin/HEAD unset; run git remote set-head origin -a)"
fi

# --- what the release run owns ----------------------------------------------

d=$(base_repo bumped); sed -i.bak 's/version: 7.0.0/version: 7.0.1/' "$d/skills/ship/SKILL.md"
check_rc "a bumped version line fails" 1 "$(rc_of "$d")"
check "the message names the file and the line" \
  "skills/ship/SKILL.md: changes a metadata.version line, which the release run owns
    -  version: 7.0.0
    +  version: 7.0.1" "$(out_of "$d")"

d=$(base_repo bumped-committed); sed -i.bak 's/version: 7.0.0/version: 8.0.0/' "$d/skills/ship/SKILL.md"
git_ "$d" add -Af && git_ "$d" commit -qm 'feat(ship)!: x'
check_rc "a bump already committed fails too" 1 "$(rc_of "$d")"

d=$(base_repo bumped-second); sed -i.bak 's/version: 1.0.2/version: 1.1.0/' "$d/skills/cloud-ship/SKILL.md"
check_rc "a bump in any skill fails" 1 "$(rc_of "$d")"

# --- what stays a hand edit --------------------------------------------------

d=$(base_repo schema); sed -i.bak 's/profile-schema: 3/profile-schema: 4/' "$d/skills/ship/SKILL.md"
check_rc "a profile-schema bump passes" 0 "$(rc_of "$d")"

d=$(base_repo prose); printf 'A new paragraph.\n' >> "$d/skills/ship/SKILL.md"
check_rc "a prose change passes" 0 "$(rc_of "$d")"

d=$(base_repo untouched)
check_rc "an unchanged tree passes" 0 "$(rc_of "$d")"

# --- adding a line is not moving one -----------------------------------------

# A new skill arrives carrying its first version line.
d=$(base_repo added); mkdir -p "$d/skills/new"
printf -- '---\nname: new\nmetadata:\n  version: 0.1.0\n---\n' > "$d/skills/new/SKILL.md"
git_ "$d" add -Af
check_rc "a new skill's first version line passes" 0 "$(rc_of "$d")"

# A skill that had no metadata block gains one, in a file that was already there.
# `--diff-filter` cannot see this: the file is modified, and only the absence of a
# removed version line says the number was not moved.
d=$(base_repo gains-a-block)
printf -- '---\nname: setup-skills\nmetadata:\n  version: 4.0.1\n---\n\n# setup-skills\n' \
  > "$d/skills/setup-skills/SKILL.md"
check_rc "a version line the file did not have passes" 0 "$(rc_of "$d")"

# A skill removed takes its version line with it, and that is not a bump either.
d=$(base_repo deleted); git_ "$d" rm -q "skills/cloud-ship/SKILL.md"
check_rc "a deleted skill passes" 0 "$(rc_of "$d")"

# --- adversarial inputs, per the coding standards ----------------------------

# The documented `sed -n 's/^  version: //p'` idiom is a version line to a grep
# that reads the key and not the value, and rewording the sentence removes it.
d=$(base_repo idiom)
sed -i.bak "s|^Read the version with|Read ship's version with|" "$d/skills/ship/SKILL.md"
check_rc "the sed idiom reworded is not a version line" 0 "$(rc_of "$d")"

# A version line outside a skill is not this rule's: the release run owns the
# three under skills/ and nothing else.
d=$(base_repo elsewhere); sed -i.bak 's/version: 9.9.9/version: 9.9.10/' "$d/docs/note.md"
check_rc "a version line outside skills/ passes" 0 "$(rc_of "$d")"

# --- tooling -----------------------------------------------------------------

check_rc "a root that is not a checkout is tooling" 2 "$(rc_of "$fixture/nope")"
check_rc "a base ref that does not resolve is tooling" 2 \
  "$(bash scripts/version-line-check.sh no-such-ref "$(base_repo reffail)" >/dev/null 2>&1; printf '%s' "$?")"
check_rc "no base ref is tooling" 2 \
  "$(bash scripts/version-line-check.sh >/dev/null 2>&1; printf '%s' "$?")"

finish
