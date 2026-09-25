#!/usr/bin/env bash
# scripts/house-style-check.sh: the em-dash ban and the whitespace rules. The
# em-dash cases' subject is the verdict's
# independence from the locale: the cloud sandbox runs with LANG and LC_ALL
# empty, where a `$'\u'` escape stays escape text and the check matched
# its own source (issue #249). Each case runs under both an empty locale and
# C.UTF-8, against a throwaway checkout that carries a copy of the check itself.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
check_script=$PWD/scripts/house-style-check.sh

# <case>: a checkout with a clean skill and the check under scripts/; prints its path.
checkout() {
  local d="$fixture/$1"
  mkdir -p "$d/skills/x" "$d/scripts" || return 1
  printf 'plain text - with a hyphen\n' > "$d/skills/x/SKILL.md"
  cp "$check_script" "$d/scripts/"
  git -C "$d" init -q && git -C "$d" add -A
  printf '%s' "$d"
}
# <locale> <dir>
rc_of()  { (cd "$2" && LANG='' LC_ALL=$1 bash scripts/house-style-check.sh >/dev/null 2>&1); printf '%s' "$?"; }
out_of() { (cd "$2" && LANG='' LC_ALL=$1 bash scripts/house-style-check.sh 2>/dev/null); }

for loc in "" C.UTF-8; do
  label=${loc:-empty}
  check_rc "the current tree passes under the $label locale" 0 "$(rc_of "$loc" .)"

  d=$(checkout "clean-$label")
  check_rc "a clean checkout carrying the check passes under the $label locale" 0 "$(rc_of "$loc" "$d")"

  d=$(checkout "dash-$label")
  printf 'one \342\200\224 two\n' > "$d/skills/x/SKILL.md"; git -C "$d" add -A
  check_rc "a real em dash fails under the $label locale" 1 "$(rc_of "$loc" "$d")"
  check "the finding names the file under the $label locale" \
    "skills/x/SKILL.md:1:one $(printf '\342\200\224') two" "$(out_of "$loc" "$d" | tail -n 1)"
done

# Trailing whitespace: a derived repo's stock `trailing-whitespace` hook fails on
# a copied script that carries one (issue #288). No locale enters this rule.
d=$(checkout trailing-space)
printf 'text \n' > "$d/skills/x/SKILL.md"; git -C "$d" add -A
check_rc "a trailing space fails" 1 "$(rc_of C.UTF-8 "$d")"
check "the finding names the line" "skills/x/SKILL.md:1:text " "$(out_of C.UTF-8 "$d" | tail -n 1)"

d=$(checkout trailing-tab)
printf 'text\t\n' > "$d/skills/x/SKILL.md"; git -C "$d" add -A
check_rc "a trailing tab fails" 1 "$(rc_of C.UTF-8 "$d")"

d=$(checkout no-final-newline)
printf 'text' > "$d/skills/x/SKILL.md"; git -C "$d" add -A
check_rc "a file without a final newline fails" 1 "$(rc_of C.UTF-8 "$d")"
check "the finding names the file" "skills/x/SKILL.md" "$(out_of C.UTF-8 "$d" | tail -n 1)"

d=$(checkout empty-file)
: > "$d/skills/x/empty.md"; git -C "$d" add -A
check_rc "an empty file passes" 0 "$(rc_of C.UTF-8 "$d")"

# Tooling: outside a checkout there is no listing, which is not a clean tree.
mkdir -p "$fixture/no-checkout"
(cd "$fixture/no-checkout" && GIT_CEILING_DIRECTORIES=$fixture bash "$check_script" >/dev/null 2>&1)
check_rc "a run outside a checkout is tooling" 2 "$?"

finish
