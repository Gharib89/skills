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
cat > "$d/base-fresh.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"fresh":true}\n'
exit 0
EOF
check_rc "a mechanic that takes no positional is exempt from check 2" 0 "$(rc_of "$d")"

# Check 3: the Bash 3.2 target. A file under skills/ runs in whatever shell a
# consumer machine provides, macOS's system Bash included, and the mechanics
# carry no `set -e`, so a Bash 4 builtin there is a skipped line and a silent
# pass rather than a stop. One case per named construct, because each is its own
# branch of the pattern.
mechanics=ship/scripts/read-issue.sh

d=$(copy_skills bash4-mapfile)
printf '\nmapfile -t lines < /dev/null\n' >> "$d/$mechanics"
check_rc "a mapfile under skills/ fails the check" 1 "$(rc_of skills/ship/scripts "$d")"

d=$(copy_skills bash4-readarray)
printf '\nreadarray -t lines < /dev/null\n' >> "$d/$mechanics"
check_rc "a readarray under skills/ fails the check" 1 "$(rc_of skills/ship/scripts "$d")"

d=$(copy_skills bash4-assoc)
printf '\ndeclare -A seen\n' >> "$d/$mechanics"
check_rc "a declare -A under skills/ fails the check" 1 "$(rc_of skills/ship/scripts "$d")"

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

# A tree the check cannot read is tooling, exit 2, never a pass: an unsearchable
# skills tree reported as clean is the silent pass the rule exists to prevent.
check_rc "an unreadable skills tree is tooling, not a pass" 2 "$(rc_of skills/ship/scripts "$fixture/absent")"

finish
