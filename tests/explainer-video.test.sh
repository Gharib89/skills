#!/usr/bin/env bash
# explainer-video's Node tests, `tests/explainer-video/*.test.mjs`, under
# `node --test`. Each drives the skill's scripts as a process against a temp
# tool cache, with the canned backend `fake-backend.mjs` selected through
# EXPLAINER_VIDEO_BACKEND, so none reaches the network or installs a thing.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

command -v node >/dev/null || { echo "FAIL explainer-video: node not on PATH" >&2; exit 1; }

out=$(node --test tests/explainer-video/*.test.mjs 2>&1)
rc=$?
[ "$rc" -eq 0 ] || printf '%s\n' "$out" | grep -E '^not ok|^# (pass|fail)|AssertionError|Error|expected|actual' | head -40 >&2
check_rc "node --test tests/explainer-video" 0 "$rc"

finish
