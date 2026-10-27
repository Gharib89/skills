#!/usr/bin/env bash
# creative-video's Node tests, `tests/creative-video/*.test.mjs`, under
# `node --test`. Each drives the skill's scripts as a process or its modules
# against a temp tool cache, with the canned backend `fake-backend.mjs` selected
# through CREATIVE_VIDEO_BACKEND, so none reaches the network or installs a
# thing. `backend-concat` runs the real ffmpeg, skipped where it is not on PATH.
# The whole set runs well inside the turn rung's 60 s, so it has no `--turn`
# selector.
#
#   tests/creative-video.test.sh
#
# exit: 0 pass · 1 fail
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source tests/lib.sh

command -v node >/dev/null || { echo "FAIL creative-video: node not on PATH" >&2; exit 1; }

out=$(node --test --test-timeout=180000 tests/creative-video/*.test.mjs 2>&1)
rc=$?
[ "$rc" -eq 0 ] || printf '%s\n' "$out" | grep -E '^not ok|^# (pass|fail)|AssertionError|Error|expected|actual' | head -40 >&2
check_rc "node --test tests/creative-video" 0 "$rc"

finish
