#!/usr/bin/env bash
# The source-repo refresh line a consumer runs reinstalls every skill its lock
# records from Gharib89/skills, in any case, beside the four Ship needs, so a
# skill installed beyond those four is never held back at its old version. A
# lock jq cannot read stops the line before the installer, which given no
# `--skill` installs every skill in the repo, and a lock key stays one literal
# argument, never shell text the line runs. Each printed line (update-skills
# step 2, the `### Ship` block's) is run in a scratch directory over a fixture
# lock, `npx` a function that prints its arguments. No call here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/good" "$tmp/bad" "$tmp/empty" "$tmp/blank"
printf '{"skills": {\n' >"$tmp/bad/skills-lock.json"
: >"$tmp/empty/skills-lock.json"
printf '  \n' >"$tmp/blank/skills-lock.json"
cat >"$tmp/good/skills-lock.json" <<'EOF'
{"skills": {
  "grill-with-artifact": {"source": "gharib89/skills"},
  "setup-harness": {"source": "Gharib89/skills"},
  "ship": {"source": "Gharib89/skills"},
  "tdd": {"source": "mattpocock/skills"},
  "x$(echo INJECTED)": {"source": "gharib89/skills"}
}}
EOF

# Runs the refresh line in <file> from <dir>, the chained preflight dropped.
refresh() {
  local cmd
  cmd=$(grep -o 'flags=$(jq[^`]*' "$1" | head -1 | sed 's/ && \.claude.*//')
  [ -n "$cmd" ] || { echo "no refresh line"; return 1; }
  (cd "$2" && npx() { printf '%s\n' "$@"; } && eval "$cmd") 2>/dev/null
}

# The --skill names the line in <file> installs over the good lock, sorted.
installed() { refresh "$1" "$tmp/good" | grep -A1 -x -- --skill | grep -v -- '^--' | sort; }

want=$(printf '%s\n' cloud-ship grill-with-artifact setup-harness setup-skills ship update-skills 'x$(echo INJECTED)' | sort)
check "update-skills step 2 refreshes every source-repo lock entry" "$want" "$(installed skills/update-skills/SKILL.md)"
check "the ### Ship block's refresh line does too" "$want" "$(installed skills/setup-skills/ship-block.md)"
for f in skills/update-skills/SKILL.md skills/setup-skills/ship-block.md; do
  for lock in bad empty blank; do
    out=$(refresh "$f" "$tmp/$lock"); rc=$?
    check "$f: a $lock lock never reaches the installer" "" "$out"
    [ "$rc" -ne 0 ] || check_rc "$f: a $lock lock fails the line" 1 0
  done
done

finish
