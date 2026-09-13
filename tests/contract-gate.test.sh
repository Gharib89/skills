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
rc_of() { bash scripts/contract-check.sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }

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

finish
