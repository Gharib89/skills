#!/usr/bin/env bash
# explainer-video's Node tests, `tests/explainer-video/*.test.mjs`, under
# `node --test`. Each drives the skill's scripts as a process against a temp
# tool cache, with the canned backend `fake-backend.mjs` selected through
# EXPLAINER_VIDEO_BACKEND, so none reaches the network or installs a thing.
#
#   tests/explainer-video.test.sh [--turn]
#
# `--turn` is the harness's turn rung, which has 60 s: it leaves out the files
# that run the render and gates pipeline once per case, `gates-*` and
# `render-*`, which together take longer than that. The full rung and the local
# gate run `tests/run.sh`, which passes no flag and so runs every file.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

command -v node >/dev/null || { echo "FAIL explainer-video: node not on PATH" >&2; exit 1; }

files=(tests/explainer-video/*.test.mjs)
if [ "${1:-}" = --turn ]; then
  kept=()
  for f in "${files[@]}"; do
    case ${f##*/} in gates-*.test.mjs | render-*.test.mjs) ;; *) kept+=("$f") ;; esac
  done
  files=("${kept[@]}")
fi
out=$(node --test "${files[@]}" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || printf '%s\n' "$out" | grep -E '^not ok|^# (pass|fail)|AssertionError|Error|expected|actual' | head -40 >&2
check_rc "node --test tests/explainer-video" 0 "$rc"

finish
