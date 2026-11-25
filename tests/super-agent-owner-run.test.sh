#!/usr/bin/env bash
# An owner-run entry (#1381, `ledger take`, "I'll take <thread>"): the owner took the
# thread, so reconcile never counts a stall on it, never lists it as settled, at
# rest or owing cleanup (the super agent would otherwise merge it or clean up the
# owner's worktree), `take` clears the entry's open needs, one `owner-run` row
# reminds the owner after 3 days and not again, and the status block lists it under
# `Yours`. The clock is pinned through SA_NOW. Fake `t3` and `gh` are on PATH.
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
repo=acme/widgets
key=$repo#1
t0=1795000000 # 2026-11-18T11:06:40Z
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
R() { SA_NOW=${1:-$t0} bash "$s/reconcile.sh" --ledger "$led"; }
L add --repo $repo --number 1 --thread th-1 --worktree /wt/1 --branch feat/x-1 >/dev/null
sa_thread th-1 idle 1 0 /wt/1 feat/x-1; sa_pr $repo feat/x-1 none; sa_issue $repo 1 open

# --- take clears the entry's needs, and marks it -----------------------------------------
L need $key --action "Ask widgets#1 about the run" --reason owner-steered --why w --option a --option b >/dev/null
out=$(L take $key); rc=$?
check "take answers the mark" "0 true" "$rc $(jq -r .owner_run <<<"$out")"
check "and the entry's open needs are gone" 0 "$(L list | jq '[.needs[] | select(.key == "acme/widgets#1")] | length')"
check "take of a key not in the ledger exits 1" 1 "$(L take $repo#99 >/dev/null 2>&1; echo $?)"
L set $key owner_run_since '"2026-11-17T11:06:40Z"' >/dev/null

# --- reconcile: no stall, no settle or cleanup row, no step-in -------------------------------
R >/dev/null
sa_thread th-1 idle 2 0 /wt/1 feat/x-1
out=$(R $((t0 + 2000)))
check "a run that ended and a rest past the window count no stall" "0 0" "$(jq -r '"\(.stalled | length) \(.entries[0].stalls)"' <<<"$out")"
check "no row names the entry but the status block's Yours" "0 0 0 0" \
  "$(jq -r '"\(.escalate | length) \(.at_rest | length) \(.settled | length) \(.cleanup | length)"' <<<"$out")"
sa_pr $repo feat/x-1 merged; sa_issue $repo 1 closed
out=$(R $((t0 + 2100)))
check "its PR merged and its issue closed: the entry ends, owing no cleanup and no settle row" "settled null 0 0" \
  "$(jq -r '"\(.entries[0].stage) \(.entries[0].cleanup_owed // "null") \(.settled | length) \(.cleanup | length)"' <<<"$out")"
sa_pr $repo feat/x-1 none; sa_issue $repo 1 open

# --- one reminder after 3 days, and not again ----------------------------------------------------
L add --repo $repo --number 2 --thread th-2 --worktree /wt/2 --branch feat/x-2 >/dev/null
sa_thread th-2 idle 1 0 /wt/2 feat/x-2; sa_pr $repo feat/x-2 none; sa_issue $repo 2 open
L take $repo#2 >/dev/null
rows() { jq -c '[.escalate[] | select(.reason == "owner-run") | .key]'; }
L set $repo#2 owner_run_since '"2026-11-16T11:06:41Z"' >/dev/null
check "just under 3 days: no reminder" '[]' "$(R | rows)"
L set $repo#2 owner_run_since '"2026-11-15T11:06:40Z"' >/dev/null
out=$(R)
check "at 3 days: one owner-run row, naming the key and asking watch or drop" '["acme/widgets#2"] still yours: watch or drop?' \
  "$(rows <<<"$out") $(jq -r '.escalate[] | select(.reason == "owner-run") | .detail' <<<"$out")"
check "and the entry is marked reminded" true "$(L get $repo#2 | jq -r .owner_run_reminded)"
check "the next reconcile does not remind again" '[]' "$(R $((t0 + 3600)) | rows)"
check "the reminder takes no other row for the entry" 0 "$(R $((t0 + 7200)) | jq '[.escalate[] | select(.key == "acme/widgets#2")] | length')"

# --- the status block lists it under Yours, with its PR state and its age ----------------------------
out=$(SA_NOW=$t0 bash "$s/status.sh" --ledger "$led" --digest)
check "Yours names the entry, its PR state and how long it has been the owner's (3 days)" \
  'Yours (1): [widgets#2](https://github.com/acme/widgets/issues/2) no PR, yours for 3 days' "$(jq -r .block <<<"$out" | grep '^Yours')"
check "and it is on no Running row" 0 "$(jq -r .block <<<"$out" | grep -c '^Running')"

# --- an entry a 0.45.0 super agent paused reads as owner-run (#1381 review) -------------------------------------
L add --repo $repo --number 3 --thread th-3 --worktree /wt/3 --branch feat/x-3 >/dev/null
sa_thread th-3 idle 1 0 /wt/3 feat/x-3; sa_pr $repo feat/x-3 none; sa_issue $repo 3 open
L set $repo#3 paused true >/dev/null
# The pause date a 0.45.0 ledger holds is the entry's last update before the upgrade.
paused_at=$(jq -r '.entries["acme/widgets#3"].updated_at' "$led")
R $((t0 + 10000)) >/dev/null
sa_thread th-3 idle 2 0 /wt/3 feat/x-3
out=$(R $((t0 + 20000)))
check "its run and its rest count no stall, and no row names it" "0 0" \
  "$(jq -r '"\(.stalled | length) \([.escalate[] | select(.key == "acme/widgets#3")] | length)"' <<<"$out")"
check "it is owner-run now, its start the last update before the upgrade, and no paused mark" "true $paused_at false" \
  "$(L get $repo#3 | jq -r '"\(.owner_run) \(.owner_run_since) \(has("paused"))"')"

finish
