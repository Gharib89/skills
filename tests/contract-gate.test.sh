#!/usr/bin/env bash
# scripts/contract-check.sh: the mechanics' malformed-invocation contract.
# Each case runs the checker against a copy of the real scripts directory, so a
# fixture shares the real exclusion list and the real guards; only the mutation
# under test differs from a tree that passes.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <case-dir>: a fresh copy of the mechanics, for one mutation.
copy() { local d="$fixture/$1"; rm -rf "$d"; cp -r skills/ship/scripts "$d"; printf '%s' "$d"; }
# <case-dir>: a fresh copy of the whole skills tree, for one Bash 4+ mutation.
copy_skills() { local d="$fixture/$1"; rm -rf "$d"; cp -r skills "$d"; printf '%s' "$d"; }
rc_of() { bash scripts/contract-check.sh "$1" "${2:-skills}" >/dev/null 2>&1; printf '%s' "$?"; }
# The checker's own stdout, for the cases that assert which violation it named.
out_of() { bash scripts/contract-check.sh "$1" "${2:-skills}" 2>/dev/null; }

# The real skills tree is the second argument here, so this case holds check 3
# as well: the tree that ships carries no Bash 4+ construct outside the
# setup-skills template.
check_rc "the current tree holds the contract" 0 "$(rc_of "$(copy clean)")"

# A mechanic written with the pre-#62 idiom: bash's own diagnostic on stderr and
# exit 1, where the contract wants one JSON object and exit 2.
d=$(copy expansion)
printf '\nx=${2:?needs a thing}\n' >> "$d/read-issue.sh"
check_rc "a \${N:?} expansion fails the check" 1 "$(rc_of "$d")"

# `${N?msg}` fails the same way as `${N:?msg}`: exit 1, bash's diagnostic on
# stderr, no JSON. The ban covers both forms.
d=$(copy expansion-no-colon)
printf '\nx=${2?needs a thing}\n' >> "$d/read-issue.sh"
check_rc "a \${N?} expansion fails the check" 1 "$(rc_of "$d")"

# The expansion is banned under the whole directory, host adapters included.
d=$(copy expansion-host)
printf '\nx=${1:?needs a thing}\n' >> "$d/host/github.sh"
check_rc "a \${N:?} expansion in a host adapter fails the check" 1 "$(rc_of "$d")"

d=$(copy exit-one)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
echo "read-issue: missing issue" >&2
exit 1
EOF
check_rc "a positional-taking mechanic exiting 1 bare fails the check" 1 "$(rc_of "$d")"

d=$(copy no-json)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
echo "usage: read-issue <issue>" >&2
exit 2
EOF
check_rc "exit 2 without a JSON error object fails the check" 1 "$(rc_of "$d")"

# The four mechanics that legitimately take no argument are not held to check 2:
# a bare invocation of one is a real run, not a malformed invocation.
d=$(copy excluded)
# The stub answers --help because check 5 exempts nobody: without that branch
# the fixture would fail on check 5 and the case would assert the wrong thing.
cat > "$d/base-fresh.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = --help ] && { echo "usage: base-fresh"; exit 0; }
printf '{"fresh":true}\n'
exit 0
EOF
check_rc "a mechanic that takes no positional is exempt from check 2" 0 "$(rc_of "$d")"

# Check 4: a flag typed where the id belongs. A stub rather than the real
# mechanic with its guard removed, because an unguarded mechanic reaches the
# host and no test here does.
d=$(copy dash-as-id)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
usage='usage: read-issue <issue>'
[ -n "${1:-}" ] || { printf '{"error":"%s"}\n' "$usage"; exit 2; }
printf '{"number":"%s"}\n' "$1"
EOF
check_rc "a mechanic that reads a leading-dash value as its id fails the check" 1 "$(rc_of "$d")"

# Why check 4 invokes three arities: a mechanic with more than one positional
# answers a single `--x` on its missing-second-positional guard, which is the
# usage line for the wrong reason, and passes.
d=$(copy dash-as-id-third)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
usage='usage: read-issue <issue>'
[ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -n "${3:-}" ] || { printf '{"error":"%s"}\n' "$usage"; exit 2; }
printf '{"number":"%s"}\n' "$1"
EOF
check_rc "a three-positional mechanic is caught only by the third dash" 1 "$(rc_of "$d")"

# Check 5: the --help contract. Each stub answers checks 2 and 4 the way a real
# mechanic does, so the one violation in the fixture is the one under test and
# the checker's whole stdout is the line it names.
help_stub() { # <case-dir> <help-branch>
  local d; d=$(copy "$1")
  { printf '#!/usr/bin/env bash\n'
    printf "usage='usage: read-issue <issue>'\n"
    [ -n "$2" ] && printf '%s\n' "$2"
    printf 'case ${1:-} in ""|-*) printf %s "$usage"; exit 2 ;; esac\n' "'{\"error\":\"%s\"}\\n'"
    printf 'printf %s "$1"\n' "'{\"number\":\"%s\"}\\n'"
  } > "$d/read-issue.sh"
  printf '%s' "$d"
}

d=$(help_stub help-unanswered '')
check "a mechanic that does not answer --help is named" \
  'read-issue: --help exited 2, expected 0' "$(out_of "$d")"
check_rc "a mechanic that does not answer --help fails the check" 1 "$(rc_of "$d")"

d=$(help_stub help-wrong-line '[ "${1:-}" = --help ] && { echo "see the docs"; exit 0; }')
check "a --help answer that is not the usage line is named" \
  'read-issue: --help did not print its own usage line on stdout' "$(out_of "$d")"
check_rc "a --help answer that is not the usage line fails the check" 1 "$(rc_of "$d")"

d=$(help_stub help-noisy '[ "${1:-}" = --help ] && { echo "$usage"; echo noise >&2; exit 0; }')
check "a --help answer that writes to stderr is named" \
  'read-issue: --help wrote to stderr' "$(out_of "$d")"
check_rc "a --help answer that writes to stderr fails the check" 1 "$(rc_of "$d")"

# The mechanic's name has to end where its own usage line ends it. A prefix
# match alone takes another mechanic's line as this one's.
d=$(help_stub help-name-prefix '[ "${1:-}" = --help ] && { echo "usage: read-issue-other <issue>"; exit 0; }')
check "a --help answer naming a longer mechanic is named" \
  'read-issue: --help did not print its own usage line on stdout' "$(out_of "$d")"
check_rc "a --help answer naming a longer mechanic fails the check" 1 "$(rc_of "$d")"

# The usage line and nothing under it. A case pattern matches across newlines,
# so the prefix arm above passes a mechanic that prints its usage and then talks.
d=$(help_stub help-extra-output '[ "${1:-}" = --help ] && { echo "usage: read-issue <issue>"; echo "and some more"; exit 0; }')
check "a --help answer with a second line is named" \
  'read-issue: --help printed more than its usage line on stdout' "$(out_of "$d")"
check_rc "a --help answer with a second line fails the check" 1 "$(rc_of "$d")"

# Check 3: the Bash 3.2 target. A file under skills/ runs in whatever shell a
# consumer machine provides, macOS's system Bash included, and the mechanics
# carry no `set -e`, so a Bash 4 builtin there is a skipped line and a silent
# pass rather than a stop. One case per named construct, because each is its own
# branch of the pattern.
mechanics=ship/scripts/read-issue.sh

d=$(copy_skills bash4-mapfile)
printf '\nmapfile -t lines < /dev/null\n' >> "$d/$mechanics"
check_rc "a mapfile under skills/ fails the check" 1 "$(rc_of skills/ship/scripts "$d")"

# A command name ends at any character a name cannot carry, not at whitespace
# alone: `mapfile<f` and `mapfile;` are the same builtin.
d=$(copy_skills bash4-redirect)
printf '\nmapfile</dev/null\n' >> "$d/$mechanics"
check_rc "a mapfile delimited by a redirect fails the check" 1 "$(rc_of skills/ship/scripts "$d")"

d=$(copy_skills bash4-readarray)
printf '\nreadarray -t lines < /dev/null\n' >> "$d/$mechanics"
check_rc "a readarray under skills/ fails the check" 1 "$(rc_of skills/ship/scripts "$d")"

d=$(copy_skills bash4-assoc)
printf '\ndeclare -A seen\n' >> "$d/$mechanics"
check_rc "a declare -A under skills/ fails the check" 1 "$(rc_of skills/ship/scripts "$d")"

# `-A` need not stand alone or come first: every spelling is the same array.
for form in '-r -A' '-A -r' '-Ar'; do
  d=$(copy_skills "bash4-assoc-$(printf '%s' "$form" | tr -d ' -')")
  printf '\ndeclare %s seen\n' "$form" >> "$d/$mechanics"
  check_rc "a declare $form under skills/ fails the check" 1 "$(rc_of skills/ship/scripts "$d")"
done

# The lowercase options are Bash 3.2's own and must not be flagged.
d=$(copy_skills bash3-indexed-array)
printf '\ndeclare -ar plain\n' >> "$d/$mechanics"
check_rc "a declare -ar does not fail the check" 0 "$(rc_of skills/ship/scripts "$d")"

d=$(copy_skills bash4-lowercase)
printf '\nx=${reason,,}\n' >> "$d/$mechanics"
check_rc "a \${var,,} under skills/ fails the check" 1 "$(rc_of skills/ship/scripts "$d")"

# A positional or `$@` takes the same case modifier, and the pattern covers it:
# `${1,,}` is as absent from Bash 3.2 as `${reason,,}` is.
d=$(copy_skills bash4-positional)
printf '\nx=${1,,}\n' >> "$d/$mechanics"
check_rc "a \${1,,} under skills/ fails the check" 1 "$(rc_of skills/ship/scripts "$d")"

d=$(copy_skills bash4-uppercase)
printf '\nx=${reason^^}\n' >> "$d/$mechanics"
check_rc "a \${var^^} under skills/ fails the check" 1 "$(rc_of skills/ship/scripts "$d")"

# The setup-skills local gate is a template written into a consumer repo as that
# repo's own repo-local gate, behind its own Bash 4 version guard. It is
# repo-local for this rule, so the check never reads it.
d=$(copy_skills bash4-template)
printf '\nmapfile -t lines < /dev/null\n' >> "$d/setup-skills/local-gate.sh"
check_rc "the setup-skills local-gate template is exempt" 0 "$(rc_of skills/ship/scripts "$d")"

# A construct named in a comment is prose, not a call: preflight.sh explains in
# one why it uses a read loop instead of mapfile, and that comment must survive.
d=$(copy_skills bash4-comment)
printf '\n# a read loop, not mapfile: the mechanics target Bash 3.2\n' >> "$d/$mechanics"
check_rc "a construct named in a comment does not fail the check" 0 "$(rc_of skills/ship/scripts "$d")"

# Both exclusions read a field, not the whole line. A violation whose own content
# carries the shape of the other exclusion is still a violation.
d=$(copy_skills bash4-shadowed-comment)
printf '\ndeclare -A seen # path:12: # a note\n' >> "$d/$mechanics"
check_rc "a violation carrying :N: # in its content still fails" 1 "$(rc_of skills/ship/scripts "$d")"

d=$(copy_skills bash4-shadowed-template)
printf '\nmapfile -t x < "%s/setup-skills/local-gate.sh:"\n' "$d" >> "$d/$mechanics"
check_rc "a violation naming the exempt template still fails" 1 "$(rc_of skills/ship/scripts "$d")"

# A tree the check cannot read is tooling, exit 2, never a pass: an unsearchable
# skills tree reported as clean is the silent pass the rule exists to prevent.
# Two ways it can be unreadable, and the second is the one the grep status owns.
check_rc "an absent skills tree is tooling, not a pass" 2 "$(rc_of skills/ship/scripts "$fixture/absent")"

# Root reads through a 000 directory, so there the search would succeed and the
# case would assert the wrong thing.
if [ "$(id -u)" -ne 0 ]; then
  d=$(copy_skills grep-failure)
  chmod 000 "$d/ship"
  rc=$(rc_of skills/ship/scripts "$d")
  chmod 755 "$d/ship"
  check_rc "a search the tree refuses is tooling, not a pass" 2 "$rc"
fi

finish
