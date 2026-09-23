#!/usr/bin/env bash
# scripts/house-style-check.sh: the em-dash ban. The subject is the verdict's
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

finish
