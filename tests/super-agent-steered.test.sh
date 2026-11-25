#!/usr/bin/env bash
# An owner-steered thread (#1381): the newest message from outside the thread is the
# owner's, newer than the entry's `held_since`. `reply.sh` reads the author out of a
# `t3_thread_read` (`owner_at`), and `reconcile --reads` marks the entry `steered`:
# its stalls are 0 and no `stalled` row, no nudge, and after the stall window at rest
# one `owner-steered` escalate row asks "watch or take?". A message from the super
# agent (`createdBy: agent`) as the newest one clears the mark. The status block's
# Running row ends `(you spoke last)`. The clock is pinned through SA_NOW. Fake
# `t3` and `gh` are on PATH.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake" "$tmp/reads"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=acme/widgets
key=$repo#1
t0=1795000000 # 2026-11-18T11:06:40Z
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
R() { SA_NOW=$1 bash "$s/reconcile.sh" --ledger "$led" --reads "$tmp/reads"; }
# read_of <author of the newest user message> <its updatedAt>: a t3_thread_read of th-1
read_of() {
  jq -cn --arg by "$1" --arg at "$2" '
    {thread: {threadId: "th-1", status: "idle", runCount: 1, pendingRequestCount: 0, worktreePath: "/wt/1", branch: "feat/x-1", updatedAt: $at},
     items: [{position: 1, type: "user_message", createdBy: "agent", text: "/ship-run 1", updatedAt: "2026-11-10T09:00:00.000Z"},
             {position: 2, type: "assistant_message", createdBy: "agent", text: "working", updatedAt: "2026-11-10T09:30:00.000Z"},
             {position: 3, type: "user_message", createdBy: $by, text: "try the other way", updatedAt: $at}],
     hasMore: false}' > "$tmp/read.json"
}

# --- reply.sh reads who spoke last ---------------------------------------------------------------
read_of user 2026-11-18T10:00:00.000Z
out=$(bash "$s/reply.sh" "$tmp/read.json" --dir "$tmp/reads"); rc=$?
check "the reply of a thread whose newest user message the owner typed names its time" "0 2026-11-18T10:00:00.000Z" "$rc $(jq -r .owner_at "$tmp/reads/th-1.json")"
read_of agent 2026-11-18T10:00:00.000Z; bash "$s/reply.sh" "$tmp/read.json" --dir "$tmp/reads" >/dev/null
check "a super agent send as the newest message leaves owner_at null" null "$(jq -r .owner_at "$tmp/reads/th-1.json")"
read_of system 2026-11-18T10:00:00.000Z; bash "$s/reply.sh" "$tmp/read.json" --dir "$tmp/reads" >/dev/null
check "so does a system message" null "$(jq -r .owner_at "$tmp/reads/th-1.json")"

# --- reconcile marks it steered, counts no stall, then asks once per window ---------------------------
L add --repo $repo --number 1 --thread th-1 --worktree /wt/1 --branch feat/x-1 >/dev/null
L set $key launched_at '"2026-11-10T09:00:00Z"' >/dev/null
L set $key stalls 2 >/dev/null
sa_pr $repo feat/x-1 none; sa_issue $repo 1 open
sa_thread th-1 idle 1 0 /wt/1 feat/x-1
read_of user 2026-11-18T10:00:00.000Z; bash "$s/reply.sh" "$tmp/read.json" --dir "$tmp/reads" >/dev/null
out=$(R $t0)
check "the entry is steered and its stalls are reset to 0" "true 0" "$(L get $key | jq -r '"\(.steered) \(.stalls)"')"
check "no stalled row, no escalate row on the first look" "0 0" "$(jq -r '"\(.stalled | length) \(.escalate | length)"' <<<"$out")"
sa_thread th-1 idle 2 0 /wt/1 feat/x-1
out=$(R $((t0 + 500)))
check "a run that ended inside the window counts no stall either" "0 0 0" "$(jq -r '"\(.stalled | length) \(.entries[0].stalls) \(.escalate | length)"' <<<"$out")"
out=$(R $((t0 + 1000)))
check "past the stall window at rest: one owner-steered row, never a nudge" '[{"key":"acme/widgets#1","reason":"owner-steered"}] 0' \
  "$(jq -c '[.escalate[] | {key, reason}]' <<<"$out") $(jq '.stalled | length' <<<"$out")"
check "and the row asks watch or take" "at rest after your message: watch or take?" "$(jq -r '.escalate[0].detail' <<<"$out")"
check "the window restarts: no second row at once" 0 "$(R $((t0 + 1100)) | jq '.escalate | length')"
out=$(R $((t0 + 2000)))
check "and again after the next window, until the owner decides" "1 0" "$(jq -r '"\(.escalate | length) \(.stalled | length)"' <<<"$out")"
check "a recorded need stands in for the row" 0 "$(L need $key --action "ask" >/dev/null; R $((t0 + 3000)) | jq '[.escalate[] | select(.reason == "owner-steered")] | length')"
L unneed $key >/dev/null 2>&1

# --- the status block says the owner spoke last ----------------------------------------------------------
L set $key stage '"running"' >/dev/null 2>&1
sa_stage "$led" $key running; L set $key observed '{"gate":false,"pr":{"number":5,"state":"open"}}' >/dev/null
out=$(SA_NOW=$t0 bash "$s/status.sh" --ledger "$led" --digest)
check "a steered entry's Running row ends (you spoke last)" 1 "$(jq -r .block <<<"$out" | grep -c '^Running.*widgets#1.*(you spoke last)$')"

# --- the super agent's own message is the newest: the mark clears ------------------------------------------
read_of agent 2026-11-18T12:00:00.000Z; bash "$s/reply.sh" "$tmp/read.json" --dir "$tmp/reads" >/dev/null
sa_thread th-1 idle 2 0 /wt/1 feat/x-1; sa_stage "$led" $key at-rest
R $((t0 + 4000)) >/dev/null
check "no owner message from outside the thread: no longer steered" false "$(L get $key | jq -r .steered)"
out=$(SA_NOW=$t0 bash "$s/status.sh" --ledger "$led" --digest)
check "and the Running row loses its mark" 0 "$(jq -r .block <<<"$out" | grep -c 'you spoke last')"
# a message the owner sent before the adoption is not steering it
read_of user 2026-11-18T10:00:00.000Z; bash "$s/reply.sh" "$tmp/read.json" --dir "$tmp/reads" >/dev/null
L set $key held_since '"2026-11-18T10:30:00Z"' >/dev/null
R $((t0 + 5000)) >/dev/null
check "a thread whose owner message is older than held_since is not steered" false "$(L get $key | jq -r .steered)"

finish
