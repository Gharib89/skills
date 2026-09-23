#!/usr/bin/env bash
# scripts/contract-check.sh: the mechanics' malformed-invocation contract.
# The first case runs the checker against the real `skills/ship/scripts`, and
# every case under it runs it once against a fixture of its own, asserting on
# the exit code and the stdout that one run left behind: the verdict and the
# violation it names are two readings of the same run.
#
# A fixture carries `_lib.sh`, the real host adapters and only the mechanics the
# case's own mutation is read through, rather than a copy of all of them. Checks
# 2, 4 and 5 spawn each mechanic in the directory up to six times, which is
# nearly all of what a full-tree run costs, and on a fixture it is spent
# re-asserting what the first case asserts once against the real tree. The
# guards a fixture does share are the real ones, copied in. Together the two
# take this file from 64 s to 2.5 s.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT

# <case-dir> [<mechanic>...]: a mechanics directory for one case, always
# carrying `_lib.sh` and the real host adapters, plus a real copy of each named
# mechanic for a case that mutates one rather than replacing it.
copy_mechanics() {
  local d="$fixture/$1" m; shift
  rm -rf "$d"; mkdir -p "$d"
  cp skills/ship/scripts/_lib.sh "$d/" || exit 2
  cp -r skills/ship/scripts/host "$d/" || exit 2
  # A mechanic renamed out from under this file would otherwise leave the case
  # appending its mutation to a file holding nothing else, still green.
  for m; do cp "skills/ship/scripts/$m.sh" "$d/" || exit 2; done
  printf '%s' "$d"
}
# <case-dir>: a fresh copy of the whole skills tree, for one Bash 4+ mutation.
copy_skills() { local d="$fixture/$1"; rm -rf "$d"; cp -r skills "$d"; printf '%s' "$d"; }

# Run the checker once and leave its exit code in `rc` and its stdout in `out`,
# which is what every assertion below reads.
run() { out=$(bash scripts/contract-check.sh "$1" "${2:-skills}" 2>/dev/null); rc=$?; }

# 0 when the last run's stdout contains this line, for a fixture that trips more
# than one check and whose whole stdout is therefore not one assertion's
# business.
named() { case $out in *"$1"*) printf 0 ;; *) printf 1 ;; esac; }

# A mechanics directory with no mechanic in it: checks 1, 2, 4 and 5 have
# nothing of their own to read, so the verdict is check 3's alone, which is the
# only check a `copy_skills` fixture mutates.
inert=$(copy_mechanics inert)

# The real mechanics and the real skills tree, so this case holds every check
# against the directory that ships, check 3 included: the tree carries no
# Bash 4+ construct outside the setup-skills template.
run skills/ship/scripts
check_rc "the current tree holds the contract" 0 "$rc"

# A mechanic written with the pre-#62 idiom: bash's own diagnostic on stderr and
# exit 1, where the contract wants one JSON object and exit 2.
d=$(copy_mechanics expansion read-issue)
printf '\nx=${2:?needs a thing}\n' >> "$d/read-issue.sh"
run "$d"
check_rc "a \${N:?} expansion fails the check" 1 "$rc"

# `${N?msg}` fails the same way as `${N:?msg}`: exit 1, bash's diagnostic on
# stderr, no JSON. The ban covers both forms.
d=$(copy_mechanics expansion-no-colon read-issue)
printf '\nx=${2?needs a thing}\n' >> "$d/read-issue.sh"
run "$d"
check_rc "a \${N?} expansion fails the check" 1 "$rc"

# The expansion is banned under the whole directory, host adapters included.
d=$(copy_mechanics expansion-host)
printf '\nx=${1:?needs a thing}\n' >> "$d/host/github.sh"
run "$d"
check_rc "a \${N:?} expansion in a host adapter fails the check" 1 "$rc"

d=$(copy_mechanics exit-one)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
echo "read-issue: missing issue" >&2
exit 1
EOF
run "$d"
check_rc "a positional-taking mechanic exiting 1 bare fails the check" 1 "$rc"

d=$(copy_mechanics no-json)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
echo "usage: read-issue <issue>" >&2
exit 2
EOF
run "$d"
check_rc "exit 2 without a JSON error object fails the check" 1 "$rc"

# The four mechanics that legitimately take no argument are not held to check 2:
# a bare invocation of one is a real run, not a malformed invocation.
d=$(copy_mechanics excluded)
# The stub answers --help because check 5 exempts nobody: without that branch
# the fixture would fail on check 5 and the case would assert the wrong thing.
cat > "$d/base-fresh.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = --help ] && { echo "usage: base-fresh"; exit 0; }
printf '{"fresh":true}\n'
exit 0
EOF
run "$d"
check_rc "a mechanic that takes no positional is exempt from check 2" 0 "$rc"

# Check 4: a flag typed where the id belongs. A stub rather than the real
# mechanic with its guard removed, because an unguarded mechanic reaches the
# host and no test here does.
d=$(copy_mechanics dash-as-id)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
usage='usage: read-issue <issue>'
[ -n "${1:-}" ] || { printf '{"error":"%s"}\n' "$usage"; exit 2; }
printf '{"number":"%s"}\n' "$1"
EOF
run "$d"
check_rc "a mechanic that reads a leading-dash value as its id fails the check" 1 "$rc"

# Why check 4 invokes three arities: a mechanic with more than one positional
# answers a single `--x` on its missing-second-positional guard, which is the
# usage line for the wrong reason, and passes.
d=$(copy_mechanics dash-as-id-third)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
usage='usage: read-issue <issue>'
[ -n "${1:-}" ] && [ -n "${2:-}" ] && [ -n "${3:-}" ] || { printf '{"error":"%s"}\n' "$usage"; exit 2; }
printf '{"number":"%s"}\n' "$1"
EOF
run "$d"
check_rc "a three-positional mechanic is caught only by the third dash" 1 "$rc"

# Check 5: the --help contract. Each stub answers checks 2 and 4 the way a real
# mechanic does, so the one violation in the fixture is the one under test and
# the checker's whole stdout is the line it names.
help_stub() { # <case-dir> <help-branch>
  local d; d=$(copy_mechanics "$1")
  { printf '#!/usr/bin/env bash\n'
    printf "usage='usage: read-issue <issue>'\n"
    [ -n "$2" ] && printf '%s\n' "$2"
    printf 'case ${1:-} in ""|-*) printf %s "$usage"; exit 2 ;; esac\n' "'{\"error\":\"%s\"}\\n'"
    printf 'printf %s "$1"\n' "'{\"number\":\"%s\"}\\n'"
  } > "$d/read-issue.sh"
  printf '%s' "$d"
}

run "$(help_stub help-unanswered '')"
check "a mechanic that does not answer --help is named" \
  'read-issue: --help exited 2, expected 0' "$out"
check_rc "a mechanic that does not answer --help fails the check" 1 "$rc"

run "$(help_stub help-wrong-line '[ "${1:-}" = --help ] && { echo "see the docs"; exit 0; }')"
check "a --help answer that is not the usage line is named" \
  'read-issue: --help did not print its own usage line on stdout' "$out"
check_rc "a --help answer that is not the usage line fails the check" 1 "$rc"

run "$(help_stub help-noisy '[ "${1:-}" = --help ] && { echo "$usage"; echo noise >&2; exit 0; }')"
check "a --help answer that writes to stderr is named" \
  'read-issue: --help wrote to stderr' "$out"
check_rc "a --help answer that writes to stderr fails the check" 1 "$rc"

# The mechanic's name has to end where its own usage line ends it. A prefix
# match alone takes another mechanic's line as this one's.
run "$(help_stub help-name-prefix '[ "${1:-}" = --help ] && { echo "usage: read-issue-other <issue>"; exit 0; }')"
check "a --help answer naming a longer mechanic is named" \
  'read-issue: --help did not print its own usage line on stdout' "$out"
check_rc "a --help answer naming a longer mechanic fails the check" 1 "$rc"

# The usage line and nothing under it. A case pattern matches across newlines,
# so the prefix arm above passes a mechanic that prints its usage and then talks.
run "$(help_stub help-extra-output '[ "${1:-}" = --help ] && { echo "usage: read-issue <issue>"; echo "and some more"; exit 0; }')"
check "a --help answer with a second line is named" \
  'read-issue: --help printed more than its usage line on stdout' "$out"
check_rc "a --help answer with a second line fails the check" 1 "$rc"

# A guard placed after `ship_load_host` answers --help correctly wherever an
# adapter loads, which is why check 5 runs from a directory with no origin
# remote. This stub answers checks 2 and 4 from the repo, and only check 5,
# from there, sees the adapter error where the usage line belongs.
d=$(copy_mechanics help-late-guard)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: read-issue <issue>'
ship_load_host
ship_help "$usage" "$@"
case ${1:-} in ""|-*) ship_tooling "$usage" ;; esac
printf '{"number":"%s"}\n' "$1"
EOF
run "$d"
check "a guard after the adapter load is named" \
  'read-issue: --help exited 2, expected 0' "$out"
check_rc "a guard after the adapter load fails the check" 1 "$rc"

# The --help answer and the guards' answer are two paths, and check 4 reads only
# the second. A mechanic that grows a flag and updates one of them leaves the
# other as the run's stale source.
run "$(help_stub help-drift '[ "${1:-}" = --help ] && { echo "usage: read-issue"; exit 0; }')"
check "a --help answer that disagrees with the guard is named" \
  'read-issue: --help and the usage guard print different lines' "$out"
check_rc "a --help answer that disagrees with the guard fails the check" 1 "$rc"

# The drift comparison reaches the mechanics that take no positional too: only
# `base-fresh` and `select` answer a bad call with no usage line at all. The
# call that reaches the guard differs per mechanic, and `file-issue`, which
# carries the longest usage string in the tree, answers the bare call, not
# check 4's three dashes.
d=$(copy_mechanics help-drift-no-positional)
cat > "$d/file-issue.sh" <<'EOF'
#!/usr/bin/env bash
usage='usage: file-issue --title <title> --body-file <path> --label <marker>'
[ "${1:-}" = --help ] && { printf '%s\n' "$usage"; exit 0; }
printf '{"error":"%s [--distinct-from <n>[,<n>]]"}\n' "$usage"
exit 2
EOF
run "$d"
check "a no-positional mechanic whose --help drifts from its guard is named" \
  'file-issue: --help and the usage guard print different lines' "$out"
check_rc "a no-positional mechanic whose --help drifts fails the check" 1 "$rc"

# Check 4 takes the usage line and nothing under it, the way check 5 does: the
# regex anchors the start alone. This stub trips check 5's comparison too, so the
# assertion names check 4's own line rather than the whole stdout.
d=$(copy_mechanics dash-usage-extra)
cat > "$d/read-issue.sh" <<'EOF'
#!/usr/bin/env bash
usage='usage: read-issue <issue>'
[ "${1:-}" = --help ] && { printf '%s\n' "$usage"; exit 0; }
case ${1:-} in ""|-*) printf '{"error":"%s\\nand more"}\n' "$usage"; exit 2 ;; esac
printf '{"number":"%s"}\n' "$1"
EOF
run "$d"
check_rc "a usage error with a second line is named by check 4" 0 \
  "$(named 'read-issue: 1 leading-dash positional(s) did not answer with its own usage line')"
check_rc "a usage error with a second line fails the check" 1 "$rc"

# Check 3: the Bash 3.2 target. A file under skills/ runs in whatever shell a
# consumer machine provides, macOS's system Bash included, and the mechanics
# carry no `set -e`, so a Bash 4 builtin there is a skipped line and a silent
# pass rather than a stop. One case per named construct, because each is its own
# branch of the pattern. The mechanics directory is `inert`.
mechanics=ship/scripts/read-issue.sh

d=$(copy_skills bash4-mapfile)
printf '\nmapfile -t lines < /dev/null\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a mapfile under skills/ fails the check" 1 "$rc"

# A command name ends at any character a name cannot carry, not at whitespace
# alone: `mapfile<f` and `mapfile;` are the same builtin.
d=$(copy_skills bash4-redirect)
printf '\nmapfile</dev/null\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a mapfile delimited by a redirect fails the check" 1 "$rc"

d=$(copy_skills bash4-readarray)
printf '\nreadarray -t lines < /dev/null\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a readarray under skills/ fails the check" 1 "$rc"

d=$(copy_skills bash4-assoc)
printf '\ndeclare -A seen\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a declare -A under skills/ fails the check" 1 "$rc"

# `-A` need not stand alone or come first: every spelling is the same array.
for form in '-r -A' '-A -r' '-Ar'; do
  d=$(copy_skills "bash4-assoc-$(printf '%s' "$form" | tr -d ' -')")
  printf '\ndeclare %s seen\n' "$form" >> "$d/$mechanics"
  run "$inert" "$d"
  check_rc "a declare $form under skills/ fails the check" 1 "$rc"
done

# The lowercase options are Bash 3.2's own and must not be flagged.
d=$(copy_skills bash3-indexed-array)
printf '\ndeclare -ar plain\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a declare -ar does not fail the check" 0 "$rc"

d=$(copy_skills bash4-lowercase)
printf '\nx=${reason,,}\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a \${var,,} under skills/ fails the check" 1 "$rc"

# A positional or `$@` takes the same case modifier, and the pattern covers it:
# `${1,,}` is as absent from Bash 3.2 as `${reason,,}` is.
d=$(copy_skills bash4-positional)
printf '\nx=${1,,}\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a \${1,,} under skills/ fails the check" 1 "$rc"

d=$(copy_skills bash4-uppercase)
printf '\nx=${reason^^}\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a \${var^^} under skills/ fails the check" 1 "$rc"

# The setup-skills local gate is a template written into a consumer repo as that
# repo's own repo-local gate, behind its own Bash 4 version guard. It is
# repo-local for this rule, so the check never reads it.
d=$(copy_skills bash4-template)
printf '\nmapfile -t lines < /dev/null\n' >> "$d/setup-skills/local-gate.sh"
run "$inert" "$d"
check_rc "the setup-skills local-gate template is exempt" 0 "$rc"

# A construct named in a comment is prose, not a call: preflight.sh explains in
# one why it uses a read loop instead of mapfile, and that comment must survive.
d=$(copy_skills bash4-comment)
printf '\n# a read loop, not mapfile: the mechanics target Bash 3.2\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a construct named in a comment does not fail the check" 0 "$rc"

# Both exclusions read a field, not the whole line. A violation whose own content
# carries the shape of the other exclusion is still a violation.
d=$(copy_skills bash4-shadowed-comment)
printf '\ndeclare -A seen # path:12: # a note\n' >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a violation carrying :N: # in its content still fails" 1 "$rc"

d=$(copy_skills bash4-shadowed-template)
printf '\nmapfile -t x < "%s/setup-skills/local-gate.sh:"\n' "$d" >> "$d/$mechanics"
run "$inert" "$d"
check_rc "a violation naming the exempt template still fails" 1 "$rc"

# SHIP_HOST_ADAPTER swaps the host adapter for the test suite's Host fake, so
# `ship_load_host` in `_lib.sh` is its one reader. The untouched copy carries
# that reader and passes; a mechanic that reads it fails, named.
d=$(copy_skills host-adapter-lib)
run "$inert" "$d"
check_rc "the one reader in _lib.sh passes" 0 "$rc"

d=$(copy_skills host-adapter-mechanic)
printf '\nadapter=${SHIP_HOST_ADAPTER:-}\n' >> "$d/ship/scripts/read-issue.sh"
run "$inert" "$d"
check_rc "a mechanic reading SHIP_HOST_ADAPTER fails" 1 "$rc"
check "and the violation names the mechanic" 0 "$(named "$d/ship/scripts/read-issue.sh:")"

# A tree the check cannot read is tooling, exit 2, never a pass: an unsearchable
# skills tree reported as clean is the silent pass the rule exists to prevent.
# Two ways it can be unreadable, and the second is the one the grep status owns.
run "$inert" "$fixture/absent"
check_rc "an absent skills tree is tooling, not a pass" 2 "$rc"

# Root reads through a 000 directory, so there the search would succeed and the
# case would assert the wrong thing.
if [ "$(id -u)" -ne 0 ]; then
  d=$(copy_skills grep-failure)
  chmod 000 "$d/ship"
  run "$inert" "$d"
  chmod 755 "$d/ship"
  check_rc "a search the tree refuses is tooling, not a pass" 2 "$rc"
fi

finish
