#!/usr/bin/env bash
# scripts/live-run-ship.sh: the live run's driver, over stub tools in a
# throwaway state directory. A fake `gh` keeps the fixture's issues, PRs and
# branches as files and clones a local seed repo, with a bare repo as its origin
# where a PR's head is pushed as `refs/pull/<n>/head`; a fake `claude` plays one
# scripted outcome per invocation (a Ship that reaches the merge gate, stops
# ambiguous, fails a check, claims a vague issue, hits a cap, or fails to start)
# and writes the Run file and host state that outcome leaves; `npx` is a no-op.
# Asserted: the result line and exit code, which carry the pass rule (one retry
# per path), the caps and the unavailable cases.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

source tests/live-run-lib.sh

check "both paths passing is a pass" '{"result":"pass","failed":[],"retried":[]}
rc=0' "$(drive happy ambiguous)"
check "every claude run carries the budget cap" "2" "$(grep -c -- '--max-budget-usd 2.50 ' "$LIVE_STUB/claude.log")"
check "the vague issue is filed ready for an agent" '["ready-for-agent"]' \
  "$(jq -sc '[.[] | select(.title == "Fix calc.sh the way we discussed") | .labels[].name]' "$LIVE_STUB"/issues/*.json)"
check "every run's issue is closed after it" "[]" "$(jq -sc '[.[] | select(.state == "open") | .number]' "$LIVE_STUB"/issues/*.json)"

check "an in-sync seed installs ship alone" "1" "$(wc -l < "$LIVE_STUB/npx.log")"

pin() { local e; for e in "${composes[@]}"; do [ "${e##*:}" != "$1" ] || echo "${e%:*}"; done; }
check "each composed skill the seed lacks or holds off its pin is installed at its pin" '{"result":"pass","failed":[],"retried":[]}
rc=0
skills add '"$(pin tdd) --skill tdd --agent claude-code -y
skills add $(pin find-docs) --skill find-docs --agent claude-code -y" \
  "$(MISSING=tdd OFF_PIN=find-docs drive happy ambiguous; tail -n +2 "$LIVE_STUB/npx.log")"
src=$(pin find-docs)
off_pin_reason="skill off pin: find-docs at $off_ref, pinned ${src#*#}"
check "Ship meets a clean clone with the installed pin" "${src#*#}" "$(cat "$LIVE_STUB/clone")"
check "a config hiding untracked files still leaves a clean clone" "${src#*#}" \
  "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=status.showUntrackedFiles GIT_CONFIG_VALUE_0=no \
    MISSING=tdd drive happy ambiguous >/dev/null; cat "$LIVE_STUB/clone")"
check "a failed composed-skill install is unavailable" \
  "{\"result\":\"unavailable\",\"reason\":\"composed skill install failed: $off_pin_reason\"}
rc=2" "$(OFF_PIN=find-docs NPX_FAILS=find-docs drive happy ambiguous)"
check "an install that exits 0 off its pin is unavailable" \
  "{\"result\":\"unavailable\",\"reason\":\"fixture clone fails ship's skill check: $off_pin_reason; run npx skills add $src --skill find-docs --agent claude-code -y\"}
rc=2" "$(OFF_PIN=find-docs NPX_NOOP=find-docs drive happy ambiguous)"
check "a clone the installs leave dirty is unavailable" \
  '{"result":"unavailable","reason":"the fixture clone is not clean after the installs"}
rc=2' "$(OFF_PIN=find-docs NPX_LOCKS=1 drive happy ambiguous)"

check "a pass on the retry is a pass that names the first failure" \
  '{"result":"pass","failed":[],"retried":["happy: phase 5: not closed","happy: phase 6: not closed","happy: phase 7: not closed","happy: phase 8: not closed","happy: merge gate: not reached"]}
rc=0' "$(drive happy-skips-gate happy ambiguous)"

# Usage: two attempts of happy (the first fails), one of ambiguous, each result
# carrying 3 turns and 1 child agent; tokens sum over both models.
usage_runs='[{"path":"happy","attempt":1,"input_tokens":11,"output_tokens":22,"cache_read_tokens":33,"cache_write_tokens":40,"turns":3,"subagents":1},{"path":"happy","attempt":2,"input_tokens":11,"output_tokens":22,"cache_read_tokens":33,"cache_write_tokens":40,"turns":3,"subagents":1},{"path":"ambiguous","attempt":1,"input_tokens":11,"output_tokens":22,"cache_read_tokens":33,"cache_write_tokens":40,"turns":3,"subagents":1}]'
check "each run records its usage, a retried first attempt's included" "$usage_runs" \
  "$(STUB_USAGE=1 DRIVE_KEEP='[.runs[] | {path, attempt, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, turns, subagents}]' \
    drive happy-skips-gate happy ambiguous | head -n 1)"
check "per_path sums every attempt's cost and tokens, failed ones included" \
  '[{"path":"ambiguous","passed":true,"attempts":1,"cost_usd":1,"input_tokens":11,"output_tokens":22,"cache_read_tokens":33,"cache_write_tokens":40,"turns":3,"subagents":1},{"path":"happy","passed":true,"attempts":2,"cost_usd":2,"input_tokens":22,"output_tokens":44,"cache_read_tokens":66,"cache_write_tokens":80,"turns":6,"subagents":2}]' \
  "$(STUB_USAGE=1 DRIVE_KEEP=.per_path drive happy-skips-gate happy ambiguous | head -n 1)"
# USAGE_ONCE=1: only the first claude run reports usage; per_path must not pass a partial sum off as the total.
check "per_path is null where any attempt lacked the field" '[null,2]' \
  "$(DRIVE_KEEP='[.per_path[] | select(.path == "happy") | (.input_tokens, .attempts)]' \
    USAGE_ONCE=1 STUB_USAGE=1 drive happy-skips-gate happy ambiguous | head -n 1)"
check "a token key one model omits is null, not a partial sum" '[33,null]' \
  "$(USAGE_PARTIAL=1 STUB_USAGE=1 DRIVE_KEEP='[.runs[0] | .cache_read_tokens, .cache_write_tokens]' drive happy ambiguous | head -n 1)"
check "malformed model usage keeps the attempt and reports null" '[2,null]' \
  "$(USAGE_MALFORMED=1 STUB_USAGE=1 DRIVE_KEEP='[.runs | length, .[0].input_tokens]' drive happy ambiguous | head -n 1)"
check "an unavailable tool-call count is explicit" '[true,null]' \
  "$(DRIVE_KEEP='[.runs[0] | has("tool_calls"), .tool_calls]' drive happy ambiguous | head -n 1)"
check "a cleanup failure makes its path fail despite a passing retry" '[false]' \
  "$(PR_CLOSE_FAILS=1 DRIVE_KEEP='[.per_path[] | select(.path == "happy") | .passed]' drive happy-skips-gate happy ambiguous | head -n 1)"
check "a result without usage records null, never a guess" \
  '[{"input_tokens":null,"output_tokens":null,"cache_read_tokens":null,"cache_write_tokens":null,"turns":null,"subagents":null}]' \
  "$(DRIVE_KEEP='[.runs[0] | {input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, turns, subagents}]' drive happy ambiguous | head -n 1)"

check "a retry does not hide the first attempt's cleanup failure" \
  '["happy: cleanup: left PR #101 open"]
rc=1' "$(PR_CLOSE_FAILS=1 drive happy-skips-gate happy ambiguous | { read -r line; jq -c .failed <<<"$line"; cat; })"

check "an ambiguous path that claims and opens a PR twice fails" \
  '{"result":"fail","failed":["ambiguous: stop: the reply does not name ambiguous","ambiguous: phase 1: closed","ambiguous: phase 2: opened","ambiguous: issue: claimed","ambiguous: pr: 1 open PRs close #3, want 0","ambiguous: branch: feat/x-3 pushed"],"retried":["ambiguous: stop: the reply does not name ambiguous","ambiguous: phase 1: closed","ambiguous: phase 2: opened","ambiguous: issue: claimed","ambiguous: pr: 1 open PRs close #2, want 0","ambiguous: branch: feat/x-2 pushed"]}
rc=1' "$(drive happy ambiguous-claims ambiguous-claims)"
check "the PRs and branches of a failed run are cleaned up" "[] " \
  "$(jq -c '[.[] | select(.state == "open")]' "$LIVE_STUB/pulls.json") $(cat "$LIVE_STUB/branches")"

check "the budget cap is a fail" '{"result":"fail","failed":["happy: cap: budget $2.50"],"retried":["happy: cap: budget $2.50"]}
rc=1' "$(drive budget budget ambiguous)"

check "the wall-clock cap is a fail" '{"result":"fail","failed":["happy: cap: wall clock 1 s"],"retried":["happy: cap: wall clock 1 s"]}
rc=1' "$(LIVE_RUN_WALL_S=1 drive slow slow ambiguous)"

check "an unreachable fixture repo is unavailable" '{"result":"unavailable","reason":"cannot clone Gharib89/ship-fixture"}
rc=2' "$(CLONE_FAILS=1 drive happy ambiguous)"

check "the outline is judged at the head of the PR that closes the issue" \
  '["happy: pr body: pr-body: change outline: node sub: file not found: calc.sh"]' \
  "$(drive happy-decoy happy-decoy ambiguous | head -n 1 | jq -c .failed)"

check "a PR whose head cannot be checked out is unavailable" '{"result":"unavailable","reason":"cannot check out PR #101'"'"'s head"}
rc=2' "$(drive happy-unpushed)"

check "a claude killed before the wall clock is not the cap" '{"result":"unavailable","reason":"claude -p failed"}
rc=2' "$(drive killed)"
check "claude output that is not JSON is unavailable" '{"result":"unavailable","reason":"claude -p output unreadable"}
rc=2' "$(drive happy garbled)"
check "claude exiting 0 with no output is unavailable" '{"result":"unavailable","reason":"claude -p output unreadable"}
rc=2' "$(drive happy silent)"
check "an empty reply is judged, not unavailable" '{"result":"fail","failed":["ambiguous: stop: the reply does not name ambiguous"],"retried":["ambiguous: stop: the reply does not name ambiguous"]}
rc=1' "$(drive happy no-reply no-reply)"

check "claude failing to run is unavailable" '{"result":"unavailable","reason":"claude -p failed"}
rc=2' "$(drive auth)"
check "an unavailable run still closes its issue" "[]" \
  "$(jq -sc '[.[] | select(.state == "open") | .number]' "$LIVE_STUB"/issues/*.json)"

finish
