#!/usr/bin/env bash
# Replay: a linked-machine thread rested at its merge gate and nothing woke the
# super agent (19 Nov 20:20, issue #1383; decision #1321). The thread ran on a
# linked machine, its PR was open with its checks done, so its rest raised no GitHub
# event, and the watcher of that version read a remote thread only from a reply
# file the super agent saved on a wake: the owner found the rest first, about 20
# minutes later. The fixture is hand-built on the fake `t3`, `gh` and `ssh`
# (tests/super-agent-fake.sh), the thread known only to the `t3` on the machine.
# Fixed: the watcher reads the machine's threads over SSH each poll, so the rest
# wakes it like a local one.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-on-machine-lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json fleet=$tmp/fleet.json repo=Gharib89/skills
printf '%s\n' '{"machines": {"box": {"environment_id": "env-a", "ssh": "box", "slots": 2}}}' > "$fleet"
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }

L add --repo $repo --number 9 --thread t-9 --worktree /wt/9 --branch feat/x-9 --machine box --environment env-a >/dev/null
sa_pr_head $repo feat/x-9 open abc
sa_checks $repo abc "done"
sa_issue $repo 9 open
sa_on_machine box sa_thread t-9 running 3 0 /wt/9 feat/x-9
bash "$s/reconcile.sh" --ledger "$led" --fleet "$fleet" >/dev/null 2>&1

# 20:20: the run ends on its merge-gate summary; GitHub holds nothing new
: > "$SA_FAKE/machines/box/calls"
sa_on_machine box sa_thread t-9 idle 3 0 /wt/9 feat/x-9 "ship 0.70.1: merge gate. Unmet criteria: none." 2020-01-01T00:00:00Z
out=$(bash "$s/watch.sh" --ledger "$led" --fleet "$fleet" --interval 1 --recheck 0 --timeout 3 2>/dev/null)
check "the rest at the merge gate wakes the watcher" "$repo#9 run-finished" "$(jq -r '"\(.key) \(.event)"' <<<"$out" 2>/dev/null)"
check "it read the thread on the machine, over ssh" 1 "$(grep -c 't3 thread show t-9' "$SA_FAKE/machines/box/calls" 2>/dev/null || echo 0)"
check "never with this machine's t3" 0 "$(grep -c '^t3 thread show' "$SA_FAKE/calls")"
finish
