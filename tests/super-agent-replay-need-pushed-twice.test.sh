#!/usr/bin/env bash
# Replay: one need pushed twice, and a "Nothing yet" need (19 Nov, issue #1386;
# decisions #1320 and #1358). At 09:20 and 09:51 the super agent recorded the same
# action with a different `--reason`; a repeat kept its push mark only when both
# matched, so the ledger made a new unpushed need and the owner was pushed twice. The
# same day a stall row that needed nothing from the owner yet was silenced by a need
# whose action read "Nothing yet", which then showed under `Needs you`. The incident
# version is the scripts at 177522f8 (v0.46.0 behaves as v0.37.0 here), where a need
# takes no options and no acknowledge mark exists. The fixture is hand-built on the
# fake `t3` and `gh` (tests/super-agent-fake.sh). Fixed: the second record raises
# nothing, and an acknowledge mark quiets the stall row with no `Needs you` line.
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

# 09:20, then 09:51 with another reason word
export SA_NOW
SA_NOW=$(date -d "2026-11-19 09:20" +%s)
L need $repo#5 --action "Relaunch widgets#5 on Opus" --reason stall-cap --why "it rested 3 times on one test" \
  --option "Relaunch on Opus: a fresh thread" --option "Leave it resting" >/dev/null
first=$(S | jq -c '[.raised[].key]')
SA_NOW=$(date -d "2026-11-19 09:51" +%s)
L need $repo#5 --action "Relaunch widgets#5 on Opus" --reason fault --why "it rested 3 times on one test" \
  --option "Relaunch on Opus: a fresh thread" --option "Leave it resting" >/dev/null
check "the first record raises the need" "[\"$repo#5\"]" "$first"
check "the same action under another reason word is not offered again" '[]' "$(S | jq -c '[.raised[].key]')"

# the stall row that needs nothing yet
L unneed $repo#5 >/dev/null
check "the stall row prints" "$repo#5 stall-cap" "$(R | jq -r '[.escalate[] | "\(.key) \(.reason)"] | join(",")')"
L ack $repo#5 --reason stall-cap >/dev/null
check "an acknowledge mark quiets it" '[]' "$(R | jq -c '[.escalate[].key]')"
check "without a need, the mark recorded" "[0,[\"$repo#5\"]]" "$(L list | jq -c '[(.needs // [] | length), (.acks // [] | map(.key))]')"

finish
