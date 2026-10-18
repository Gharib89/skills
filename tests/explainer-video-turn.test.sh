#!/usr/bin/env bash
# The explainer-video member's turn budget. The turn rung has 60 s and the
# member's suite takes 258 s, so `tests/explainer-video.test.sh --turn` leaves
# out the two render-heavy files and every turn row passes it; the bare call,
# which `tests/run.sh` makes for the full rung and the local gate, keeps every
# file. A stub `node` records the files it is handed, so the case runs none.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
printf '#!/bin/sh\nshift; printf "%%s\\n" "$@" > "$NODE_LOG"\n' > "$fixture/node"
chmod +x "$fixture/node"

# <flag...>: the test files the suite hands `node --test`, one basename per line.
handed() {
  export NODE_LOG=$fixture/log PATH="$fixture:$PATH"
  bash tests/explainer-video.test.sh "$@" > /dev/null 2>&1
  sed 's|.*/||' "$fixture/log"
}
all=$(for f in tests/explainer-video/*.test.mjs; do printf '%s\n' "${f##*/}"; done)

check "the bare call hands node every test file" "$all" "$(handed)"
check "--turn hands it every file but gates and render" \
  "$(printf '%s\n' "$all" | grep -v -e '^gates\.test\.mjs$' -e '^render\.test\.mjs$')" "$(handed --turn)"

# Both files named in the skip exist, or a rename would put one back on the rung.
for f in gates render; do
  if [ -f "tests/explainer-video/$f.test.mjs" ]; then have=0; else have=1; fi
  check_rc "tests/explainer-video/$f.test.mjs exists" 0 "$have"
done

# Every turn row that runs the suite passes --turn, so the rung never runs it whole.
rows=$(awk '/^TURN_ROWS=\047/ { on = 1; sub(/^TURN_ROWS=\047/, "") } on { if (sub(/\047$/, "")) { print; exit } print }' scripts/check.sh)
bad=''
while IFS='|' read -r _ member _ _ tests affected; do
  for c in "$tests" "$affected"; do
    case $c in *explainer-video.test.sh*--turn*) ;; *explainer-video.test.sh*) bad="$bad $member" ;; esac
  done
done <<EOF
$rows
EOF
check "every turn row running the suite passes --turn" "" "${bad# }"

finish
