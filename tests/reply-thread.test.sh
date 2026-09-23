#!/usr/bin/env bash
# reply-thread driven end to end over the Host fake (tests/host-fake.sh): a
# throwaway repo whose origin names GitHub so host detection still runs, and
# SHIP_HOST_ADAPTER points ship_load_host at the fake instead of host/github.sh.
# The subject is the mechanic's own envelope: {pr, thread} stamped onto a reply
# that landed, and a reply the host refused reading as replied:false with the
# host's own status merged in rather than a bare exit 1.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
T=$'\t'  # the calls log separates arguments with a tab

mech=$PWD/skills/ship/scripts/reply-thread.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh

body=$work/body.md
printf 'fixed in the next commit\n' > "$body"

run()   { ( cd "$repo" && bash "$mech" 7 t1 --body-file "$body" ); }
reset() { rm -f "$SHIP_FAKE"/*; }

reset
out=$(run); rc=$?
check_rc "a reply that lands exits 0" 0 "$rc"
check "the pr and thread are stamped onto the answer" '7 t1 true' \
  "$(jq -r '[.pr, .thread, .replied] | @tsv' <<<"$out" | tr '\t' ' ')"
check "the call the mechanic hands the host" "host_pr_reply_thread${T}7${T}t1${T}$body" \
  "$(cat "$SHIP_FAKE/calls")"

reset
: > "$SHIP_FAKE/host_pr_reply_thread.1.fail"
printf '502' > "$SHIP_FAKE/host_pr_reply_thread.1.status"
out=$(run); rc=$?
check_rc "a refused reply exits 1" 1 "$rc"
check "and reads replied:false, carrying the host's status" '7 t1 false 502' \
  "$(jq -r '[.pr, .thread, .replied, .status] | @tsv' <<<"$out" | tr '\t' ' ')"

finish
