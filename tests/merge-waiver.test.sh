#!/usr/bin/env bash
# merge on a `waiver` admission over the Host fake (#1402): a delegated ruler's
# ruling, recorded by `run-file gate admit waiver`, admits like the human's word,
# base-retargeted aside, while every other refusal still holds.
# Turn check: names merge.sh, run-file.sh and _lib.sh, whose fixture lives in tests/merge-lib.sh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/merge-lib.sh

mkdir -p "$rr/ship-wv"; : > "$rr/ship-wv/run.md"
( cd "$repo" && bash "$runfm" gate admit waiver --ruling "waive: codex outage on a docs-only PR" --head "$A" --issue wv >/dev/null 2>&1 )
reset; push_at "$A"; pr 1 open "$A" release; pr 2 merged "$A" release
printf '[{"name":"build","status":"success"}]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
runas wv 7 none "$A" >/dev/null 2>&1; rc=$?
check_rc "a waiver admits the gated head, on another base too" 0 "$rc"
check "and the gated head reaches the host's merge call" 1 "$(grep -c "^host_pr_merge${T}7${T}.*${T}$A$" "$SHIP_FAKE/calls")"
reset; push_at "$A"; pr 1 open "$A"
printf '[{"name":"build","status":"pending"}]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
out=$(runas wv 7 none "$A" 2>/dev/null); rc=$?
check "a waiver does not cover an unsettled check" "1 checks-unsettled: build: pending" "$rc $(jq -r .error <<<"$out")"
no_merge "a waiver over a running check"
mkdir -p "$rr/ship-wb"; printf '## Merge admission\n- 10:00 %s waiver\n' "$A" > "$rr/ship-wb/run.md"
reset; push_at "$A"; pr 1 open "$A"
runas wb 7 none "$A" >/dev/null 2>&1; rc=$?
check_rc "a waiver line with no ruling is no record" 1 "$rc"
no_merge "a bare waiver"
reset; push_at "$C"; pr 1 open "$C"
out=$(runas wv 7 none "$A" 2>/dev/null); rc=$?
check "a waiver does not admit a moved head" "1 head-moved: $C != $A" "$rc $(jq -r .error <<<"$out")"
check "and no merge call reaches the host past a moved head" 0 "$(cat "$SHIP_FAKE/calls" 2>/dev/null | grep -c '^host_pr_merge')"

finish
