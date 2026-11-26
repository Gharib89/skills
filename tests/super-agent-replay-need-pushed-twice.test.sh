#!/usr/bin/env bash
# Replay: one need pushed twice, and a "Nothing yet" need (19 Nov, issue #1386;
# decisions #1320 and #1358). At 09:20 and 09:51 the super agent recorded the same
# action with a different `--reason`; a repeat kept its push mark only when both
# matched, so the ledger made a new unpushed need and the owner was pushed twice. The
# same day a stall row that needed nothing from the owner yet was silenced by a need
# whose action read "Nothing yet", which then showed under `Needs you`. The incident
# version is the scripts at 177522f8 (v0.46.0 behaves as v0.37.0 here), where a need
# takes no options and no acknowledge mark exists. The fixture is hand-built on the
# fake `t3` and `gh` (tests/super-agent-fake.sh): the 09:20 need as 0.46.0 left it,
# pushed, and the 09:51 record in the form the scripts under test take (`--why` and
# options where `ledger --help` lists `--why`), so the incident version goes red at
# the reset mark. Fixed: the second record keeps the mark and raises nothing, and an
# acknowledge mark quiets the stall row with no need.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake TZ=UTC
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=acme/widgets
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
S() { bash "$s/status.sh" --ledger "$led"; }
R() { bash "$s/reconcile.sh" --ledger "$led"; }
L add --repo $repo --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null
sa_thread t-5 idle 4 0 /wt/5 feat/x-5; sa_pr $repo feat/x-5 none; sa_issue $repo 5 open
R >/dev/null
sa_stage "$led" $repo#5 at-rest
jq '.entries["acme/widgets#5"].stalls = 3' "$led" > "$led.new" && mv "$led.new" "$led"

# 09:20 recorded and pushed, then 09:51 with another reason word
jq '.needs = [{key: "acme/widgets#5", action: "Relaunch widgets#5 on Opus", reason: "stall-cap", since: "2026-11-19T09:20:00Z", pushed: true}]' \
  "$led" > "$led.new" && mv "$led.new" "$led"
export SA_NOW
SA_NOW=$(date -d "2026-11-19 09:51" +%s)
new=()
bash "$s/ledger.sh" --help 2>&1 | grep -q -- --why \
  && new=(--why "it rested 3 times on one test" --option "Relaunch on Opus: a fresh thread" --option "Leave it resting")
L need $repo#5 --action "Relaunch widgets#5 on Opus" --reason fault "${new[@]}" >/dev/null
check "the second record keeps the need marked as told" true "$(L list | jq '.needs[0] | .pushed == true or .alerted != null')"
check "and nothing is raised again" '[]' "$(S | jq -c '[(.raised // .unpushed // [])[].key]')"

# the stall row that needs nothing yet
L unneed $repo#5 >/dev/null
check "the stall row prints" "$repo#5 stall-cap" "$(R | jq -r '[.escalate[] | "\(.key) \(.reason)"] | join(",")')"
L ack $repo#5 --reason stall-cap >/dev/null
check "an acknowledge mark quiets it" '[]' "$(R | jq -c '[.escalate[].key]')"
check "without a need, the mark recorded" "[0,[\"$repo#5\"]]" "$(L list | jq -c '[(.needs // [] | length), (.acks // [] | map(.key))]')"

finish
