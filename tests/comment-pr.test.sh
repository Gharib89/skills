#!/usr/bin/env bash
# comment-pr driven end to end over the Host fake (tests/host-fake.sh): a
# throwaway repo whose origin names GitHub so host detection still runs, and
# SHIP_HOST_ADAPTER points ship_load_host at the fake instead of host/github.sh.
# The subject is the mechanic's own envelope: a post that lands, a post the
# host refuses with a status, and the call the mechanic hands the host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
T=$'\t'  # the calls log separates arguments with a tab

mech=$PWD/skills/ship/scripts/comment-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh

body=$work/body.md
printf 'round summary\n' > "$body"

run()   { ( cd "$repo" && bash "$mech" "$@" ); }
reset() { rm -f "$SHIP_FAKE"/*; }

reset
out=$(run 7 --body-file "$body"); rc=$?
check_rc "a post that lands exits 0" 0 "$rc"
check "a post that lands answers the fake's comment" \
  'https://example.invalid/pull/7#issuecomment-1' "$(jq -r .url <<<"$out")"
check "the call the mechanic hands the host" "host_pr_comment${T}7${T}$body" \
  "$(cat "$SHIP_FAKE/calls")"

reset
: > "$SHIP_FAKE/host_pr_comment.1.fail"
printf '502' > "$SHIP_FAKE/host_pr_comment.1.status"
out=$(run 7 --body-file "$body"); rc=$?
check_rc "a refused post exits 1" 1 "$rc"
check "a refused post carries the host's status" '502' "$(jq -r .status <<<"$out")"
check "and names the failure" 'comment failed' "$(jq -r .error <<<"$out")"

finish
