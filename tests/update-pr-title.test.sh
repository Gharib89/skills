#!/usr/bin/env bash
# update-pr-title driven end to end over the Host fake (tests/host-fake.sh): a
# throwaway repo whose origin names GitHub so host detection still runs, and
# SHIP_HOST_ADAPTER points ship_load_host at the fake instead of host/github.sh.
# The subject is the mechanic's own envelope: a title already equal skips the
# write entirely, a changed title is proven by the read-back rather than the
# write's exit code, and a write the host refuses carries its status.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
T=$'\t'  # the calls log separates arguments with a tab

mech=$PWD/skills/ship/scripts/update-pr-title.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh

run()   { ( cd "$repo" && bash "$mech" 7 --title "$1" ); }
reset() { rm -f "$SHIP_FAKE"/*; }

reset
printf '{"title":"fix(ship): old title"}\n'  > "$SHIP_FAKE/host_pr_get.1.json"
printf '{"title":"fix(ship): new title"}\n'  > "$SHIP_FAKE/host_pr_get.2.json"
out=$(run "fix(ship): new title"); rc=$?
check_rc "a title that differs exits 0" 0 "$rc"
check "the write is reported once read back as changed" 'fix(ship): new title true' \
  "$(jq -r '[.title, .changed] | @tsv' <<<"$out" | tr '\t' ' ')"
check "the sequence is read, write, read back" \
  "host_pr_get${T}7
host_pr_set_title${T}7${T}fix(ship): new title
host_pr_get${T}7" "$(cat "$SHIP_FAKE/calls")"

reset
printf '{"title":"fix(ship): same title"}\n' > "$SHIP_FAKE/host_pr_get.1.json"
out=$(run "fix(ship): same title"); rc=$?
check_rc "a title already equal exits 0" 0 "$rc"
check "and is reported unchanged" 'fix(ship): same title false' \
  "$(jq -r '[.title, .changed] | @tsv' <<<"$out" | tr '\t' ' ')"
check "no write reaches the host" "host_pr_get${T}7" "$(cat "$SHIP_FAKE/calls")"

reset
printf '{"title":"fix(ship): old title"}\n' > "$SHIP_FAKE/host_pr_get.1.json"
: > "$SHIP_FAKE/host_pr_set_title.1.fail"
printf '502' > "$SHIP_FAKE/host_pr_set_title.1.status"
out=$(run "fix(ship): new title"); rc=$?
check_rc "a write the host refuses exits 1" 1 "$rc"
check "and carries the host's status" '502' "$(jq -r .status <<<"$out")"

finish
