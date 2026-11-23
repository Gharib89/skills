#!/usr/bin/env bash
# update-pr-body makes no host write when the body it would publish equals the
# body the host already holds (#1345): the write would change nothing, and the
# answer keeps its shape. A changed body still writes. Driven over the Host
# fake (tests/host-fake.sh) in a throwaway checkout whose origin names GitHub.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git

mech() { ( cd "$repo" && bash "$scripts/update-pr-body.sh" "$@" ); }
wrote() { if grep -q '^host_pr_set_body' "$SHIP_FAKE/calls" 2>/dev/null; then echo yes; else echo no; fi; }
hold() { printf '{"number":7,"body":"## Summary\\n\\nsame\\n\\n## Review\\n\\n%s\\n","head_sha":"x"}\n' "$1" > "$SHIP_FAKE/host_pr_get.1.json"; }

printf 'current review\n' > "$work/review"

rm -f "$SHIP_FAKE"/*; hold 'current review'
out=$(mech 7 --section Review --body-file "$work/review" 2>/dev/null); rc=$?
check_rc "a section already matching exits 0" 0 "$rc"
check "and makes no host write" no "$(wrote)"
check "and answers in the usual shape" \
  '{"pr":7,"section":"Review","replaced":true,"created":false,"sections":["Summary","Review"]}' \
  "$(jq -c . <<<"$out")"

printf 'same\n' > "$work/pre"
rm -f "$SHIP_FAKE"/*
printf '{"number":7,"body":"same\\n\\n## Review\\n\\nx\\n","head_sha":"x"}\n' > "$SHIP_FAKE/host_pr_get.1.json"
out=$(mech 7 --preamble --body-file "$work/pre" 2>/dev/null); rc=$?
check_rc "a preamble already matching exits 0" 0 "$rc"
check "and makes no host write" no "$(wrote)"

rm -f "$SHIP_FAKE"/*; hold 'old review'
out=$(mech 7 --section Review --body-file "$work/review" 2>/dev/null); rc=$?
check_rc "a changed section exits 0" 0 "$rc"
check "and still writes" yes "$(wrote)"
finish
