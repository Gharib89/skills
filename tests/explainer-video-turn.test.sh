#!/usr/bin/env bash
# The explainer-video member's turn budget. The turn rung has 60 s and the
# member's whole suite takes longer, so `tests/explainer-video.test.sh --turn` leaves
# out the render-heavy files and every turn row passes it, with the changed
# files, so the rung runs only the tests they reach; the bare call, which
# `tests/run.sh` makes for the full rung and the local gate, keeps every file.
# A stub `node` records the files it is handed, so the case runs none.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d)
# The selector reads only the skill's and its tests' trees, so a file nothing
# names has to sit in one; not a *.test.mjs, so no suite run picks it up.
unnamed=tests/explainer-video/zz-unnamed-$$.mjs
trap 'rm -rf "$fixture" "$unnamed"' EXIT
printf '#!/bin/sh\nshift; printf "%%s\\n" "$@" > "$NODE_LOG"\n' > "$fixture/node"
chmod +x "$fixture/node"

# <flag...>: the test files the suite hands `node --test`, one basename per line.
handed() {
  export NODE_LOG=$fixture/log PATH="$fixture:$PATH"
  bash tests/explainer-video.test.sh "$@" > /dev/null 2>&1
  sed 's|.*/||' "$fixture/log" | grep '\.test\.mjs$'
}
all=$(for f in tests/explainer-video/*.test.mjs; do printf '%s\n' "${f##*/}"; done)

check "the bare call hands node every test file" "$all" "$(handed)"
check "--turn hands it every file but gates and render" \
  "$(printf '%s\n' "$all" | grep -v -e '^gates-.*\.test\.mjs$' -e '^render-.*\.test\.mjs$')" "$(handed --turn)"

# Both files named in the skip exist, or a rename would put one back on the rung.
for f in gates render; do
  if compgen -G "tests/explainer-video/$f-*.test.mjs" > /dev/null; then have=0; else have=1; fi
  check_rc "tests/explainer-video/$f-*.test.mjs exist" 0 "$have"
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

# `full` runs every row's <tests> beside the `tests` row, which already runs the
# suite whole, so the suite sits under <affected tests> alone.
whole=''
while IFS='|' read -r _ member _ _ tests _; do
  case $tests in *explainer-video.test.sh*) whole="$whole $member" ;; esac
done <<EOF
$rows
EOF
check "no turn row names the suite as its whole-suite tests" "" "${whole# }"

# The selection: `--list` prints the turn-set files the changed files reach.
# The stub `node` stays in front, so a suite that ignores `--list` runs nothing.
suite=$PWD/tests/explainer-video.test.sh
sel() { NODE_LOG=/dev/null PATH="$fixture:$PATH" bash "$suite" --turn --list "$@" 2>&1; }
turn_set=$(sel)
check "--list with no files lists the whole --turn set" \
  "$(printf '%s\n' "$all" | grep -v -e '^gates-' -e '^render-' | sed 's|^|tests/explainer-video/|')" "$turn_set"
check "an edited turn test selects itself only" \
  tests/explainer-video/terms.test.mjs "$(sel tests/explainer-video/terms.test.mjs)"
check "an edited gates or render test selects nothing on the turn rung" \
  "" "$(sel tests/explainer-video/gates-layout.test.mjs tests/explainer-video/render-core.test.mjs)"
terms=$(sel skills/explainer-video/scripts/lib/terms.mjs)
check "a source selects the test named for it" 1 \
  "$(printf '%s\n' "$terms" | grep -cx tests/explainer-video/terms.test.mjs)"
check "a source only the source tests reach selects them alone" \
  "tests/explainer-video/source-pack.test.mjs
tests/explainer-video/source-page.test.mjs
tests/explainer-video/source-repo.test.mjs" "$(sel skills/explainer-video/scripts/source/pack.mjs)"
check "a selection never reaches a gates or render file" "" \
  "$(sel skills/explainer-video/scripts/render/render.mjs | grep -e /gates- -e /render-)"
check "files are read relative to the caller's directory" "$terms" \
  "$(cd skills/explainer-video && sel scripts/lib/terms.mjs)"
check "a path through .. names the file it reaches" tests/explainer-video/terms.test.mjs \
  "$(sel tests/explainer-video/../explainer-video/terms.test.mjs)"
# page-core.js is no import: page.html names it and page-lib.mjs reads page.html.
check "a page script reaches the page tests through the page that loads it" 1 \
  "$(sel skills/explainer-video/storyboard/page-core.js | grep -cx tests/explainer-video/page.test.mjs)"

# A file the mapping cannot place selects the whole --turn set.
printf '// named by nothing\n' > "$unnamed"
for f in skills/explainer-video/scripts/gone-$$.mjs skills/explainer-video/gone-$$/x.mjs skills/explainer-video/package.json "$unnamed"; do
  check "$f selects the whole --turn set" "$turn_set" "$(sel "$f")"
done
check "one unplaceable file among placed ones selects the whole --turn set" "$turn_set" \
  "$(sel tests/explainer-video/terms.test.mjs skills/explainer-video/package.json)"

# The turn rung hands node the selection for a changed file of either member.
for f in skills/explainer-video/scripts/lib/terms.mjs tests/explainer-video/board-apply.test.mjs; do
  : > "$fixture/log"
  NODE_LOG=$fixture/log PATH="$fixture:$PATH" bash scripts/check.sh turn "$f" > /dev/null 2>&1
  check "turn on $f hands node its selection" "$(sel "$f" | sed 's|.*/||')" \
    "$(sed 's|.*/||' "$fixture/log" | grep '\.test\.mjs$')"
done

# A deleted file reaches either member's row through {paths}, so a turn that
# only deletes one still runs the whole --turn set rather than nothing.
for case in "skills/explainer-video/maintainer/gone-$$.mjs explainer-video" \
  "tests/explainer-video/gone-$$.test.mjs explainer-video-tests"; do
  f=${case% *} member=${case#* }
  : > "$fixture/log"
  out=$(NODE_LOG=$fixture/log PATH="$fixture:$PATH" bash scripts/check.sh turn "$f" 2>/dev/null)
  check "turn on deleted $f runs its row's tests" \
    "{\"rung\":\"turn\",\"verdict\":\"pass\",\"checks\":{\"tests:$member\":\"pass\"}}" "$out"
  check "and hands node the whole --turn set" "$(printf '%s\n' "$turn_set" | sed 's|.*/||')" \
    "$(sed 's|.*/||' "$fixture/log" | grep '\.test\.mjs$')"
done

finish
