#!/usr/bin/env bash
# super-agent's `ledger ruling` scope, driven through its command line: a ruling
# scoped to a repo or machine is kept with its scope, so the gate-hold step-in can
# cite the one for the run's repo, and a scope needs `--brief`. These cases moved
# here when `brief.sh` and its test were deleted.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
L() { bash "$s/ledger.sh" --ledger "$tmp/ledger.json" "$@"; }

check_rc "a repo scope without --brief exits 2" 2 "$(L ruling x --repo acme/widgets >/dev/null 2>&1; echo $?)"
L ruling "Widgets-only ruling." --brief --repo Acme/Widgets >/dev/null
L ruling "Box-only ruling." --brief --machine box >/dev/null
L ruling "Widgets on box ruling." --brief --repo acme/widgets --machine box >/dev/null
check "the ledger keeps each ruling's scope as given" '[{"repo":"Acme/Widgets","machine":null},{"repo":null,"machine":"box"},{"repo":"acme/widgets","machine":"box"}]' \
  "$(L briefed | jq -c '[.briefed[] | {repo, machine}]')"

finish
