#!/usr/bin/env bash
# super-agent's `ledger self`: the super agent's own thread id lands in the
# ledger's `own_thread` when the loop starts and is replaced at each handover.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
led=$tmp/ledger.json
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
L add --repo Gharib89/skills --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null

# --- self: the super agent's own thread id, for the wake timer and the scorecard ---
check "self records the super agent's own thread id when the loop starts" '{"own_thread":"th-first"}' "$(L self th-first | jq -c .)"
check "and the ledger holds it" th-first "$(jq -r .own_thread "$led")"
check "a handover's successor replaces it" th-second "$(L self th-second >/dev/null; jq -r .own_thread "$led")"
check "an id from T3CODE_THREAD_ID stands in for the argument" th-env "$(T3CODE_THREAD_ID=th-env L self >/dev/null; jq -r .own_thread "$led")"
entries=$(L list | jq -c .entries); L self th-third >/dev/null
check "it leaves the entries alone" "$entries" "$(L list | jq -c .entries)"
check_rc "self with no id and no T3CODE_THREAD_ID exits 2" 2 "$(env -u T3CODE_THREAD_ID bash "$s/ledger.sh" --ledger "$led" self >/dev/null 2>&1; echo $?)"

finish
