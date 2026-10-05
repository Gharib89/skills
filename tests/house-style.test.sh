#!/usr/bin/env bash
# scripts/house-style-check.sh: the em-dash ban, the whitespace rules and the
# wrap width. The em-dash cases' subject is the verdict's independence from the
# locale: the cloud sandbox runs with LANG and LC_ALL empty, where a `$'\u'`
# escape stays escape text and the check matched its own source (issue #249).
# Each runs under both an empty locale and C.UTF-8, against a throwaway checkout
# that carries a copy of the check itself.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
check_script=$PWD/scripts/house-style-check.sh

# <case>: a checkout with a clean skill and the check under scripts/; prints its path.
checkout() {
  local d="$fixture/$1"
  mkdir -p "$d/skills/x" "$d/scripts" "$d/tests" || return 1
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

# Trailing whitespace: a consumer repo's stock `trailing-whitespace` hook fails on
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

# The stock hooks skip binaries and symlinks, so neither rule reads them.
d=$(checkout binary)
printf '\000\001 ' > "$d/skills/x/icon.bin"; git -C "$d" add -A
check_rc "a binary with a trailing blank and no final newline passes" 0 "$(rc_of C.UTF-8 "$d")"

d=$(checkout symlink)
printf 'text ' > "$d/outside.txt"; ln -s ../../outside.txt "$d/skills/x/link.md"
git -C "$d" add skills
check_rc "a symlink to a file with a trailing blank and no final newline passes" 0 "$(rc_of C.UTF-8 "$d")"

# Wrap width: 80 columns over the files this repo hard-wraps, where a ragged
# reflow drew review findings. Lines no reflow can shorten are exempt.
wide=$(printf '%081d' 0 | tr 0 w)
d=$(checkout wrap-ragged)
mkdir -p "$d/skills/ship"
printf 'short line\n%s\n' "$wide" > "$d/skills/ship/SKILL.md"; git -C "$d" add -A
check_rc "an 81-column prose line in a wrapped file fails" 1 "$(rc_of C.UTF-8 "$d")"
check "the finding names the line" "skills/ship/SKILL.md:2:$wide" "$(out_of C.UTF-8 "$d" | tail -n 1)"

d=$(checkout wrap-exempt)
mkdir -p "$d/skills/ship"
{ printf -- '---\ndescription: %s\n---\n' "$wide"
  printf '```sh\n%s\n```\n' "$wide"
  printf '| %s |\n' "$wide"
  printf -- '- [%s](#%s)\n' "$wide" "$wide"
  printf '[ref]: https://example.com/%s\n' "$wide"
  printf '`%s`.\n' "$wide"
  printf '1. item\n\n     ```sh\n     %s\n     ```\n' "$wide"
} > "$d/skills/ship/SKILL.md"
printf '%s\n' "$wide" > "$d/skills/ship/CHANGELOG.md"
printf '%s\n' "$wide" > "$d/skills/x/SKILL.md"
git -C "$d" add -A
check_rc "frontmatter, fences (one nested in a list item), table, link-only and code-span-only lines, a changelog and an unwrapped file pass" 0 "$(rc_of C.UTF-8 "$d")"

# Each exemption is the whole line: prose beside a link or a code span still
# counts, a closed fence ends its exemption, and `---` opens frontmatter only on
# line 1, so a rule mid-file exempts nothing after it.
for c in "see [$wide](#a) here" "\`a\` and \`$wide\`" 'fence-closed' 'fence-other-char' 'fence-shorter' 'fence-not-opener' 'rule-mid-file'; do
  d=$(checkout "wrap-adversarial-${c:0:5}-${#c}")
  mkdir -p "$d/skills/ship"
  case $c in
    fence-closed) printf '```\nx\n```\n%s\n' "$wide" ;;
    # A fence closes only on its own character, at least as long as its opener.
    fence-other-char) printf '~~~\n```\n~~~\n%s\n' "$wide" ;;
    fence-shorter) printf '````md\n```\n````\n%s\n' "$wide" ;;
    # A backtick in a backtick opener's info string makes it an inline span.
    fence-not-opener) printf '```a`b\n%s\n' "$wide" ;;
    rule-mid-file) printf 'text\n---\n%s\n---\n' "$wide" ;;
    *) printf '%s\n' "$c" ;;
  esac > "$d/skills/ship/SKILL.md"
  git -C "$d" add -A
  check_rc "a long line fails: $c" 1 "$(rc_of C.UTF-8 "$d")"
done

# Width is counted in characters, so a multibyte character is one column under
# every locale, the empty one included.
for loc in "" C.UTF-8; do
  label=${loc:-empty}
  d=$(checkout "wrap-multibyte-$label")
  printf '%s\342\206\222\n' "$(printf '%079d' 0 | tr 0 w)" > "$d/CLAUDE.md"; git -C "$d" add -A
  check_rc "an 80-character line with a multibyte character passes under the $label locale" 0 "$(rc_of "$loc" "$d")"
  printf '%s\342\206\222\n' "$(printf '%080d' 0 | tr 0 w)" > "$d/CLAUDE.md"; git -C "$d" add -A
  check_rc "an 81-character line with a multibyte character fails under the $label locale" 1 "$(rc_of "$loc" "$d")"
done

# git grep names an unreadable file on stderr and exits 0: that is not clean.
# Root reads it anyway, so the case only runs where the mode bits bind.
if [ "$(id -u)" != 0 ]; then
  d=$(checkout unreadable)
  chmod 000 "$d/skills/x/SKILL.md"
  check_rc "an unreadable tracked file is tooling" 2 "$(rc_of C.UTF-8 "$d")"
  chmod 644 "$d/skills/x/SKILL.md"
else
  skipped "an unreadable tracked file is tooling"
fi

# chmod 000 in a test: root reads a mode-000 file, so a case built on one passes
# vacuously or fails spuriously under a root runner. The line must carry the
# `id -u` guard or sit inside an `if` whose condition does. The fixtures build
# the command from parts so this file does not trip the rule it tests.
cm="chmod 0$(printf 00)"
root_guard='[ "$(id -u)" -ne 0 ]'
root_only='[ "$(id -u)" -eq 0 ]'
unguarded_msg="tests/t.test.sh:1: $cm with no id -u root guard; root reads a mode-000 file"
d=$(checkout chmod-bare)
printf '%s f\n' "$cm" > "$d/tests/t.test.sh"
git -C "$d" add -A
check_rc "a bare mode-000 chmod in a test fails" 1 "$(rc_of C.UTF-8 "$d")"
check "the finding names the file and line and the reason" "$unguarded_msg" "$(out_of C.UTF-8 "$d" | tail -n 1)"

d=$(checkout chmod-four-zeros)
printf '%s0 f\n' "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a bare four-digit mode-0000 chmod in a test fails" 1 "$(rc_of C.UTF-8 "$d")"

d=$(checkout chmod-same-line)
printf '%s && %s f\n' "$root_guard" "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod with id -u on the same line passes" 0 "$(rc_of C.UTF-8 "$d")"

# The guard has a polarity: a same-line guard is `-eq 0 ||` or `-ne 0 &&`, and
# an enclosing if tests `-ne 0`. The inverted forms run the chmod as root.
d=$(checkout chmod-inverted-same-line)
printf '%s && %s f\n' "$root_only" "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod after an inverted same-line guard fails" 1 "$(rc_of C.UTF-8 "$d")"
check "the inverted same-line guard prints the reason" "$unguarded_msg" "$(out_of C.UTF-8 "$d" | tail -n 1)"

d=$(checkout chmod-inverted-if)
printf 'if %s; then\n  %s f\nfi\n' "$root_only" "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod inside an if on id -u -eq 0 fails" 1 "$(rc_of C.UTF-8 "$d")"
check "the inverted if guard prints the reason" "tests/t.test.sh:2: $cm with no id -u root guard; root reads a mode-000 file" "$(out_of C.UTF-8 "$d" | tail -n 1)"

d=$(checkout chmod-else-arm)
printf 'if %s; then\n  :\nelse\n  %s f\nfi\n' "$root_guard" "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod in the else arm of a root guard fails" 1 "$(rc_of C.UTF-8 "$d")"
check "the else arm prints the reason" "tests/t.test.sh:4: $cm with no id -u root guard; root reads a mode-000 file" "$(out_of C.UTF-8 "$d" | tail -n 1)"

d=$(checkout chmod-elif-guard)
printf 'if false; then\n  :\nelif %s; then\n  %s f\nfi\n' "$root_guard" "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod under an elif root guard passes" 0 "$(rc_of C.UTF-8 "$d")"

d=$(checkout chmod-early-return)
printf '%s && return\n%s f\n' "$root_only" "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod after an early return on a previous line fails" 1 "$(rc_of C.UTF-8 "$d")"

d=$(checkout chmod-eq-or)
printf '%s || %s f\n' "$root_only" "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod after id -u -eq 0 || passes" 0 "$(rc_of C.UTF-8 "$d")"

d=$(checkout chmod-in-guard)
printf 'if %s; then\n  if true; then\n    %s f\n  fi\n  %s g\nfi\n' "$root_guard" "$cm" "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod inside a guarded if, nested ifs included, passes" 0 "$(rc_of C.UTF-8 "$d")"

# The guard ends with its fi, and a one-line if opens nothing.
d=$(checkout chmod-after-guard)
printf 'if %s; then\n  true\nfi\n%s f\n' "$root_guard" "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod after its guard closed fails" 1 "$(rc_of C.UTF-8 "$d")"
check "the finding is the line after the guard" "tests/t.test.sh:4: $cm with no id -u root guard; root reads a mode-000 file" "$(out_of C.UTF-8 "$d" | tail -n 1)"

d=$(checkout chmod-oneline-if)
printf 'if true; then :; fi\n%s f\n' "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a one-line if neither opens nor closes a block" 1 "$(rc_of C.UTF-8 "$d")"

d=$(checkout chmod-unguarded-if)
printf 'if true; then\n  %s f\nfi\n' "$cm" > "$d/tests/t.test.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod inside an if with no id -u fails" 1 "$(rc_of C.UTF-8 "$d")"

d=$(checkout chmod-not-a-test); mkdir -p "$d/scripts"
printf '%s f\n' "$cm" > "$d/scripts/helper.sh"; git -C "$d" add -A
check_rc "a mode-000 chmod outside tests/*.test.sh is not this rule's" 0 "$(rc_of C.UTF-8 "$d")"

# Tooling: outside a checkout there is no listing, which is not a clean tree.
mkdir -p "$fixture/no-checkout"
(cd "$fixture/no-checkout" && GIT_CEILING_DIRECTORIES=$fixture bash "$check_script" >/dev/null 2>&1)
check_rc "a run outside a checkout is tooling" 2 "$?"
stderr=$(cd "$fixture/no-checkout" && GIT_CEILING_DIRECTORIES=$fixture bash "$check_script" 2>&1 >/dev/null)
check "tooling carries git's reason on stderr" "fatal: not a git repository" "${stderr%% (*}"

finish
