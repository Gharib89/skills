#!/usr/bin/env bash
# scripts/live-run-ship.sh's seeded-defect, red, head-moved and reviewer-outage
# paths, over the stub tools of tests/live-run-lib.sh. Asserted: each path's
# verdict, its own budget cap, the default path list, and that a Ship whose
# mechanic regressed turns head-moved or reviewer-outage red.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/live-run-lib.sh
# The seeded-defect and red paths: each filed from its own issue, each judged by
# its check, a failing first attempt kept under `retried`.
check "the defect and red paths pass on their expected outcomes" '{"result":"pass","failed":[],"retried":[]}
rc=0' "$(PATHS=defect,red drive defect-holds red-stops)"
check "each path's claude run carries its own measured budget cap" "1 1" \
  "$(grep -c -- '--max-budget-usd 2.65 ' "$LIVE_STUB/claude.log") $(grep -c -- '--max-budget-usd 0.65 ' "$LIVE_STUB/claude.log")"
check "the defect issue prescribes the unrelated proof" "true" \
  "$(jq -s 'any(.[]; .title == "Add a mul helper to calc.sh" and (.body | contains("Proof: run `stat README.md`.")))' "$LIVE_STUB"/issues/*.json)"
check "the red issue forbids editing the test it contradicts" "true" \
  "$(jq -s 'any(.[]; .title == "Make add print one more than the sum" and (.body | contains("Do not edit `test.sh`")))' "$LIVE_STUB"/issues/*.json)"
check "a run that accepts the unrelated proof fails, the first attempt under retried" \
  '{"result":"fail","failed":["defect: criterion 1: met on the seeded unrelated proof"],"retried":["defect: criterion 1: met on the seeded unrelated proof"]}
rc=1' "$(PATHS=defect drive defect-accepts defect-accepts)"
check "a red change that reaches the merge gate fails" 'true' \
  "$(PATHS=red DRIVE_KEEP='.failed | any(. == "red: issue: claimed") and any(startswith("red: pr: 1 open PRs close"))' drive red-merges red-merges | head -n 1)"
check "a red stop retried once is a pass that names the first failure" \
  '{"result":"pass","failed":[],"retried":["red: branch: feat/x-1 pushed","red: issue: claimed","red: phase 6: opened","red: phase 7: opened","red: phase 8: opened","red: phase 9: opened","red: pr: 1 open PRs close #1, want 0","red: stop: the reply names neither red-after-retry nor mis-specified"]}' \
  "$(PATHS=red DRIVE_KEEP='{result, failed, retried: (.retried | sort)}' drive red-merges red-stops | head -n 1)"
check "the script's own default runs all six paths" '["ambiguous","defect","happy","head-moved","red","reviewer-outage"]' \
  "$(DEFAULT_PATHS=1 DRIVE_KEEP='[.per_path[].path]' drive happy ambiguous defect-holds red-stops | head -n 1)"
check "an unknown path is unavailable before any run" '{"result":"unavailable","reason":"unknown path in LIVE_RUN_PATHS: bogus"}
rc=2' "$(PATHS=bogus drive)"

# The mechanic-level paths run the Ship's own mechanics: no claude run, no cost.
check "the head-moved and reviewer-outage paths pass on the real mechanics" '{"result":"pass","failed":[],"retried":[]}
rc=0' "$(PATHS=head-moved,reviewer-outage drive)"
check "and start no claude run" "absent" "$([ -e "$LIVE_STUB/claude.log" ] && echo present || echo absent)"
check "and record no cost" '[null,null]' "$(PATHS=head-moved,reviewer-outage DRIVE_KEEP='[.per_path[].cost_usd]' drive | head -n 1)"

# Failing on purpose: a Ship whose mechanic has regressed turns the path red.
mutant=$T/mutant; mkdir -p "$mutant/skills"; cp -r skills/ship "$mutant/skills/ship"
sed -i '/\[ "\$head" = "\$gated" \] || ship_fail "head-moved/d' "$mutant/skills/ship/scripts/merge.sh"
check "a merge that no longer refuses a moved head fails head-moved" "true" \
  "$(SRC=$mutant PATHS=head-moved DRIVE_KEEP='.result == "fail" and any(.failed[]; startswith("head-moved: refusal: ")) and any(.failed[]; startswith("head-moved: merge: a merge call reached the host"))' drive | head -n 1)"
rm -rf "$mutant"; mkdir -p "$mutant/skills"; cp -r skills/ship "$mutant/skills/ship"
sed -i 's/{clean: (\$held == \[\])/{clean: true/' "$mutant/skills/ship/scripts/lib/run-file-clean-gate.sh"
check "a clean gate that no longer holds on a reviewer outage fails reviewer-outage" "true" \
  "$(SRC=$mutant PATHS=reviewer-outage DRIVE_KEEP='.result == "fail" and any(.failed[]; startswith("reviewer-outage: outage: both reviewers out exited 0"))' drive | head -n 1)"


finish
