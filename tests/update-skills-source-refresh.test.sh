#!/usr/bin/env bash
# The source-repo refresh line a consumer runs reinstalls every skill its lock
# records from Gharib89/skills, in any case, beside the four Ship needs, so a
# skill installed beyond those four is never held back at its old version.
# Each printed line (update-skills step 2, the `### Ship` block's) is run in a
# scratch directory over a fixture lock, `npx` a function that prints its
# arguments. No call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/skills-lock.json" <<'EOF'
{"skills": {
  "grill-with-artifact": {"source": "gharib89/skills"},
  "setup-harness": {"source": "Gharib89/skills"},
  "ship": {"source": "Gharib89/skills"},
  "tdd": {"source": "mattpocock/skills"}
}}
EOF

# The --skill names the line in <file> installs, one per line, sorted.
installed() {
  local cmd
  cmd=$(grep -o 'npx skills add Gharib89/skills[^`]*' "$1" | head -1 | sed 's/ &&.*//')
  [ -n "$cmd" ] || { echo "no refresh line"; return; }
  (cd "$tmp" && npx() { printf '%s\n' "$@"; } && eval "$cmd") | grep -A1 -x -- --skill | grep -v -- '^--' | sort
}

want=$(printf '%s\n' cloud-ship grill-with-artifact setup-harness setup-skills ship update-skills)
check "update-skills step 2 refreshes every source-repo lock entry" "$want" "$(installed skills/update-skills/SKILL.md)"
check "the ### Ship block's refresh line does too" "$want" "$(installed skills/setup-skills/ship-block.md)"

finish
