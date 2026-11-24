#!/usr/bin/env bash
# ci-wait's bound on one host read (#1346): the wait ends at its cap even when
# the host is slow. A read that outlasts the window ends the wait as `timeout`
# and never as `green`; a read that outlasts only one call's cap (SHIP_CALL_CAP)
# answers `pending` with a cursor, the window still open; and a resumed wait keeps
# the deadline its cursor recorded, so a cursor whose window has closed times out
# without reading the host.
#
# Driven at the mechanic's own entrypoint over the Host fake (a 2 s read is a
# `.delay` entry) in a throwaway GitHub-origin checkout: no call reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship-run/scripts/ci-wait.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
repo=$work/repo
mkdir -p "$repo/docs/agents" "$SHIP_FAKE"
printf '# Ship profile\n\nSchema: 3\n\n## CI\n\nLegs: fake-leg: the fake check\nNo-checks legal: no\nPush policy: Default.\n\n## Reviewers\n' \
  > "$repo/docs/agents/ship.md"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git

reset() { rm -f "$SHIP_FAKE"/*; }
out=; rc=
ci() { out=$( cd "$repo" && SHIP_CI_WAIT_GRACE=0 bash "$mech" 7 --sha deadbee --interval 1 "$@" 2>/dev/null ); rc=$?; }
reads() { grep -c '^host_pr_get' "$SHIP_FAKE/calls" 2>/dev/null || echo 0; }

# The default fake answers green on the first read: the control.
reset
ci --timeout 60
check "a prompt read is green" green "$(jq -r .status <<<"$out")"
check_rc "and exits 0" 0 "$rc"

# A read slower than the whole window ends it at the window.
reset; echo 3 > "$SHIP_FAKE/host_pr_get.1.delay"
s=$(date +%s); ci --timeout 1; took=$(( $(date +%s) - s )) # clock-exception: proves the wait ended near its window, not after the slow read
check "a read outlasting the window is timeout, not green" timeout "$(jq -r .status <<<"$out")"
check_rc "and exits 1" 1 "$rc"
check "and the wait ended near the window, not after the read" true "$([ "$took" -lt 3 ] && echo true || echo false)"

# A read slower than one call's cap, inside a longer window, is pending.
reset; echo 3 > "$SHIP_FAKE/host_pr_get.1.delay"
SHIP_CALL_CAP=1 ci --timeout 60
check "a read outlasting the call cap is pending" pending "$(jq -r .status <<<"$out")"
check_rc "and exits 1" 1 "$rc"
check "and carries a cursor to resume the window" true "$(jq -r '.cursor | length > 0' <<<"$out")"

# A resumed wait keeps its cursor's deadline: a closed window times out unread.
cursor=$(jq -rn '{deadline: (now | floor - 5), start: (now | floor - 65), head_at: null, head_sha: "", want: "deadbee"} | tojson | @base64')
reset
( cd "$repo" && SHIP_CI_WAIT_GRACE=0 bash "$mech" 7 --cursor "$cursor" >"$work/out" 2>/dev/null ); rc=$?
check "a cursor whose window closed is timeout" timeout "$(jq -r .status "$work/out")"
check_rc "and exits 1" 1 "$rc"
check "and the host read nothing" 0 "$(reads)"

# A cursor with time left resumes its own deadline: a second slow read under the
# cap hands back a cursor carrying the first one's deadline, then a fast host is green.
reset; echo 3 > "$SHIP_FAKE/host_pr_get.1.delay"
SHIP_CALL_CAP=1 ci --timeout 60
d1=$(jq -r '.cursor | @base64d | fromjson | .deadline' <<<"$out")
cur=$(jq -r .cursor <<<"$out")
reset; echo 3 > "$SHIP_FAKE/host_pr_get.1.delay"
( cd "$repo" && SHIP_CALL_CAP=1 SHIP_CI_WAIT_GRACE=0 bash "$mech" 7 --cursor "$cur" >"$work/out" 2>/dev/null ); rc=$?
check "a resumed wait that is cut again stays pending" pending "$(jq -r .status "$work/out")"
check "and its cursor keeps the first deadline" "$d1" "$(jq -r '.cursor | @base64d | fromjson | .deadline' "$work/out")"
reset
( cd "$repo" && SHIP_CI_WAIT_GRACE=0 bash "$mech" 7 --cursor "$cur" >"$work/out" 2>/dev/null ); rc=$?
check "and a prompt host then answers green on that window" green "$(jq -r .status "$work/out")"

finish
