#!/usr/bin/env bash
# ship_title_candidates: the duplicate-title matcher behind `file-issue`.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

title='repo has no test harness, so mechanic-level unit tests have nowhere to live'
dup='{"number":10,"title":"repo has no test harness for mechanic unit tests","url":"u10"}'
other='{"number":11,"title":"merge gate summary misses the timing row","url":"u11"}'
two='{"number":12,"title":"repo test coverage is unmeasured","url":"u12"}'
open="[$dup,$other,$two]"

check "an open issue sharing three or more tokens is a candidate" \
  "[$dup]" "$(ship_title_candidates "$title" "$open" '[]')"

check "--distinct-from files past a candidate the caller judged different" \
  "[]" "$(ship_title_candidates "$title" "$open" '[10]')"

check "an unrelated title is no candidate" \
  "[]" "$(ship_title_candidates "$title" "[$other]" '[]')"

check "two shared tokens are below the floor" \
  "[]" "$(ship_title_candidates "$title" "[$two]" '[]')"

# Stopwords and tokens under four characters carry no weight, so a title made
# only of them never matches.
check "stopwords and short tokens do not make a candidate" \
  "[]" \
  "$(ship_title_candidates "$title" '[{"number":13,"title":"they have some of this","url":"u13"}]' '[]')"

finish
