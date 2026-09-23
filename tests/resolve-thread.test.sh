#!/usr/bin/env bash
# resolve-thread driven end to end over the Host fake (tests/host-fake.sh): a
# throwaway repo whose origin names GitHub so host detection still runs, and
# SHIP_HOST_ADAPTER points ship_load_host at the fake instead of host/github.sh.
# The subject is the mechanic's own envelope: {pr, thread} stamped onto the
# adapter's answer, a call that failed outright reading as ship_fail (exit 1,
# no status), and a call that answered {"resolved":false} reading exit 1 too.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/resolve-thread.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh

run()   { ( cd "$repo" && bash "$mech" 7 t1 ); }
reset() { rm -f "$SHIP_FAKE"/*; }

reset
out=$(run); rc=$?
check_rc "a resolved thread exits 0" 0 "$rc"
check "the pr and thread are stamped onto the answer" '7 t1 true' \
  "$(jq -r '[.pr, .thread, .resolved] | @tsv' <<<"$out" | tr '\t' ' ')"
check "the call the mechanic hands the host" $'host_pr_resolve_thread\t7\tt1' \
  "$(cat "$SHIP_FAKE/calls")"

# A call the host refuses outright uses ship_fail, which carries no status: the
# .status beside .fail documents that the mechanic drops it, not that it reads it.
reset
: > "$SHIP_FAKE/host_pr_resolve_thread.1.fail"
printf '502' > "$SHIP_FAKE/host_pr_resolve_thread.1.status"
out=$(run); rc=$?
check_rc "a refused call exits 1" 1 "$rc"
check "and names the failure, carrying no status" 'resolve call failed' \
  "$(jq -r .error <<<"$out")"
check "the status the host offered is dropped" false "$(jq 'has("status")' <<<"$out")"

reset
printf '{"resolved":false}\n' > "$SHIP_FAKE/host_pr_resolve_thread.1.json"
out=$(run); rc=$?
check_rc "an answer that did not resolve the thread exits 1" 1 "$rc"
check "and the answer still names the thread" '7 t1 false' \
  "$(jq -r '[.pr, .thread, .resolved] | @tsv' <<<"$out" | tr '\t' ' ')"

finish
