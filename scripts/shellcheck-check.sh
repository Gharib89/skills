#!/usr/bin/env bash
# The shellcheck lint over the source tree's scripts plus the gate itself; the
# derived copies are covered by `derived-copies` proving them identical.
# `-P SCRIPTDIR` resolves the `source "$(dirname ...)/_lib.sh"` idiom the
# mechanics use. The `shellcheck` gate in scripts/local-gate.sh runs this, in
# every lane.
#
# A system `shellcheck` on PATH is used as is. Otherwise `npx -y shellcheck`
# fetches one, and a fetch that fails before any linting runs, as the cloud
# sandbox's proxy refuses it (issue #249), is exit 2 so the gate reads
# `unavailable` rather than grading a missing tool as a lint finding.
#
#   scripts/shellcheck-check.sh
#
# stdout: shellcheck's findings
# exit: 0 clean · 1 a finding · 2 no shellcheck could be obtained
set -uo pipefail

mapfile -t files < <(git ls-files 'skills/*.sh' 'skills/**/*.sh' 'scripts/*.sh' 'tests/*.sh')
[ ${#files[@]} -gt 0 ] || { echo "no shell scripts tracked"; exit 1; }

if command -v shellcheck >/dev/null; then
  sc=(shellcheck)
elif command -v npx >/dev/null && npx -y shellcheck --version >/dev/null 2>&1; then
  sc=(npx -y shellcheck)
else
  echo "shellcheck unavailable: none on PATH, and npx could not fetch one"
  exit 2
fi
"${sc[@]}" -x -s bash -P SCRIPTDIR -S warning "${files[@]}" || exit 1
