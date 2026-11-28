#!/usr/bin/env bash
# Replay: a task settled at its first rest (9 and 15 Nov, issue #1388; decision #1318).
# On 9 Nov a grill was recorded with no interactive kind, so `reconcile` settled it at
# its first rest, while it waited on the owner's answer, and the PR it later opened
# merged unseen (incident version v0.11.0). On 15 Nov one long task on a linked machine
# settled at its first rest the same way, and the super agent re-added its thread four
# times under new slugs (`task:<slug>`, `-b`, `-c`, `-d`) to keep watching it (incident
# version 9b9900f6, v0.23.0). The fixture is hand-built on the fake `t3` and `gh`
# (tests/super-agent-fake.sh), and drives only verbs those versions have (`ledger add
# --task`, `adopt`, `reconcile`), passing `--interactive` only where `ledger --help`
# lists it, so the incident version goes red at the settled stage, not on a usage error.
# Fixed: an interactive task survives its first rest, a one-off task resting on no
# `Result:` line is not settled, and a second adopt of its thread is the same entry.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
R() { bash "$s/reconcile.sh" --ledger "$led"; }
ia=()
grep -q -- --interactive <<<"$(L --help 2>&1)" && ia=(--interactive)

# 9 Nov: the grill asks the owner and rests
L add --task grill-auth --thread t-g "${ia[@]}" >/dev/null
sa_thread t-g running 0 0 '' ''
R >/dev/null
sa_thread t-g idle 1 0 '' '' "Which cache do we keep? 1. Redis 2. In memory" 2020-01-01T00:00:00Z
out=$(R)
check "the grill survives its first rest" at-rest "$(L get task:grill-auth | jq -r .stage)"
check "nothing settled" 0 "$(jq '.settled | length' <<<"$out")"
check "and it counts no stall" 0 "$(L get task:grill-auth | jq -r .stalls)"

# 15 Nov: the long task rests between its phases, then is adopted again
L adopt --task long-run --thread t-l >/dev/null
sa_thread t-l running 0 0 '' ''
R >/dev/null
sa_thread t-l idle 1 0 '' '' "Phase 1 done; phase 2 runs next." 2020-01-01T00:00:00Z
R >/dev/null
check "a task resting on no Result: line is not settled" at-rest "$(L get task:long-run | jq -r .stage)"
out=$(L adopt --task long-run --thread t-l 2>/dev/null)
check "a second adopt of its thread is the same entry" true "$(jq -r '.existing // false' <<<"$out" 2>/dev/null)"
L adopt --task long-run-b --thread t-l >/dev/null 2>&1
check "a re-add under a new slug makes no second entry" 1 "$(L list | jq '[.entries[] | select(.thread == "t-l")] | length')"

finish
