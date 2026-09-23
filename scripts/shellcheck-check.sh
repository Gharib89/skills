#!/usr/bin/env bash
# The shellcheck lint over the source tree's scripts plus the gate itself; the
# derived copies are covered by `derived-copies` proving them identical.
# `-P SCRIPTDIR` resolves the `source "$(dirname ...)/_lib.sh"` idiom the
# mechanics use. The `shellcheck` gate in scripts/local-gate.sh runs this, in
# every lane.
#
# Uses a system `shellcheck` on PATH, else fetches one with `npx -y shellcheck`.
# When neither yields a shellcheck (for example, the cloud sandbox's proxy
# refuses the fetch, issue #249), exit 2: the gate reads that as `unavailable`,
# a missing tool, and keeps exit 1 for lint findings.
#
#   scripts/shellcheck-check.sh
#
# stdout: shellcheck's findings
# exit: 0 clean · 1 a finding · 2 no shellcheck could be obtained
set -uo pipefail

# A read loop rather than `mapfile`, so a Bash 3.2 run lists the scripts too
# instead of reading as a lint failure over an empty list.
files=()
while IFS= read -r f; do files+=("$f"); done \
  < <(git ls-files 'skills/*.sh' 'skills/**/*.sh' 'scripts/*.sh' 'tests/*.sh')
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
