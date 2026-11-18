#!/usr/bin/env bash
# super-agent's ledger shrinking, driven through `reconcile` and `ledger` over
# fake `t3` and `gh` on PATH (tests/super-agent-fake.sh), per ADR 0021: an entry
# settled with nothing owed moves to `<ledger>.archive.jsonl` 7 days after it
# settled, a settled triage thread is re-read for 7 days only, a ruling lapses 7
# days after its date unless pinned, and `migrate-rulings` applies the owner's
# list once. `SA_NOW` pins the clock.
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
repo=Gharib89/skills
day=86400
t0=1763467200 # 2025-11-18T12:00:00Z
R() { bash "$s/reconcile.sh" --ledger "$led"; }
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
iso() { jq -rn --argjson t "$1" '$t | todate'; }
keys() { jq -c '[.entries | keys[]]' "$led"; }

# <key> <stage> <settled epoch> <cleanup_owed json> [kind]: one entry as reconcile leaves it
entry() {
  jq -cn --arg k "$1" --arg s "$2" --arg at "$(iso "$3")" --argjson c "$4" --arg kind "${5:-ship}" \
    '{key: $k, repo: "Gharib89/skills", number: ($k | split("#")[1] | tonumber), thread: "t-\($k | split("#")[1])",
      worktree: "/wt", branch: "b", kind: $kind, stage: $s, stalls: 0,
      observed: {status: "idle", run_count: 1, pending: 0, gate: false, waiting: false, rest_at: null, pr: {number: null, state: "none"}},
      launched_at: $at, updated_at: $at, settled_at: $at, cleanup_owed: $c}'
}

# --- settled entries older than 7 days move to the archive ---------------------
jq -n --argjson a "$(entry "$repo#1" settled $((t0 - 8 * day)) false)" \
  --argjson b "$(entry "$repo#2" settled $((t0 - 6 * day)) false)" \
  --argjson c "$(entry "$repo#3" settled $((t0 - 8 * day)) true)" \
  --argjson d "$(entry "$repo#4" closed $((t0 - 9 * day)) false)" \
  '{entries: ([$a, $b, $c, $d] | map({(.key): .}) | add), rulings: []}' > "$led"
SA_NOW=$t0 R >/dev/null; rc=$?
check_rc "reconcile exits 0" 0 "$rc"
check "an entry settled 8 days ago, cleanup done, and a closed one 9 days ago leave the ledger" \
  "[\"$repo#2\",\"$repo#3\"]" "$(keys)"
check "they are lines of the archive beside the ledger, whole" "$repo#1 settled|$repo#4 closed" \
  "$(jq -r '"\(.key) \(.stage)"' "$led.archive.jsonl" | paste -sd'|')"
SA_NOW=$t0 R >/dev/null
check "a second reconcile archives nothing twice" 2 "$(wc -l < "$led.archive.jsonl" | tr -d ' ')"

# reconcile stamps the settle time, and the 7 days count from it
rm -f "$led" "$led.archive.jsonl"
L add --repo $repo --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null
sa_thread t-5 idle 1 0 /wt/5 feat/x-5
sa_pr $repo feat/x-5 merged
sa_issue $repo 5 closed
SA_NOW=$t0 R >/dev/null
check "an entry reconcile settles carries its settle time" "settled $(iso $t0)" \
  "$(jq -r --arg k "$repo#5" '.entries[$k] | "\(.stage) \(.settled_at)"' "$led")"
L set "$repo#5" cleanup_owed false >/dev/null
L set "$repo#5" verify_owed false >/dev/null
SA_NOW=$((t0 + 7 * day - 1)) R >/dev/null
check "it stays until 7 days have passed" "[\"$repo#5\"]" "$(keys)"
SA_NOW=$((t0 + 7 * day + 1)) R >/dev/null
check "and leaves once they have" "[]" "$(keys)"
L add --repo $repo --number 6 --thread t-6 --worktree /wt/6 --branch feat/x-6 >/dev/null
L set "$repo#6" verify_owed true >/dev/null
jq --arg k "$repo#6" --arg at "$(iso $((t0 - 30 * day)))" '.entries[$k] |= (.stage = "settled" | .settled_at = $at | .cleanup_owed = false)' "$led" > "$tmp/l" && mv "$tmp/l" "$led"
SA_NOW=$t0 R >/dev/null
check "a settled entry whose criteria check is still owed stays" "[\"$repo#6\"]" "$(keys)"

# --- reconcile does not re-read a triage thread settled more than 7 days ago ---
rm -f "$led" "$led.archive.jsonl" "$SA_FAKE/calls"
jq -n --argjson a "$(entry "$repo#9" settled $((t0 - 8 * day)) true triage)" \
  --argjson b "$(entry "$repo#10" settled $((t0 - 2 * day)) true triage)" \
  '{entries: ([$a, $b] | map({(.key): .}) | add), rulings: []}' > "$led"
sa_thread t-9 running 2 0 /wt b
sa_thread t-10 running 2 0 /wt b
out=$(SA_NOW=$t0 R)
check "a triage thread settled 2 days ago that runs again is woken" "[\"$repo#10\"]" "$(jq -c '[.woke[].key]' <<<"$out")"
check "one settled 8 days ago is never read" "" "$(grep -- 't-9' "$SA_FAKE/calls" || true)"
check "and stays settled" settled "$(jq -r --arg k "$repo#9" '.entries[$k].stage' "$led")"

# --- a ruling lapses 7 days after its date unless pinned -----------------------
rm -f "$led"
SA_NOW=$t0 L ruling "one-off" --allow "a call" --repo acme/widgets >/dev/null
SA_NOW=$t0 L ruling "lasting" --allow "b call" --repo acme/widgets >/dev/null
check "a ruling records its expiry, 7 days after its date, unpinned" "2025-11-25 false" \
  "$(jq -r '.rulings[0] | "\(.expires) \(.pinned)"' "$led")"
reads() { # <now>: the rulings each read answers
  printf '%s %s %s' "$(SA_NOW=$1 L list | jq -c '[.rulings[].text]')" \
    "$(SA_NOW=$1 L allowed | jq -c '[.allowed[].call]')" "$(SA_NOW=$1 L scoped | jq -c '[.scoped[].text]')"
}
check "on its expiry day every read still answers it" '["one-off","lasting"] ["a call","b call"] ["one-off","lasting"]' \
  "$(reads $((t0 + 7 * day)))"
out=$(SA_NOW=$t0 L pin 2025-11-18 "lasting"); rc=$?
check_rc "pin exits 0" 0 "$rc"
check "pin answers the ruling it pinned" '[{"date":"2025-11-18","text":"lasting","pinned":true}]' "$(jq -c '[.pinned[] | {date, text, pinned}]' <<<"$out")"
check "past its expiry a ruling is absent from every read, and a pinned one is kept" '["lasting"] ["b call"] ["lasting"]' \
  "$(reads $((t0 + 8 * day)))"
check "a lapsed ruling stays in the file" 2 "$(jq '.rulings | length' "$led")"
out=$(SA_NOW=$t0 L pin 2025-11-18 "no such ruling" 2>/dev/null); rc=$?
check_rc "pinning a ruling the ledger lacks exits 1" 1 "$rc"
check "and names the ruling" 1 "$(jq -r .error <<<"$out" | grep -c 'no ruling dated 2025-11-18 reads: no such ruling')"
jq '.rulings += [{date: "2025-11-01", text: "older, no expiry", allow: [], repo: null}]' "$led" > "$tmp/l" && mv "$tmp/l" "$led"
check "a ruling written before expiries lapses 7 days after its date" '["one-off","lasting","older, no expiry"]|["one-off","lasting"]' \
  "$(SA_NOW=$((t0 - 10 * day)) L list | jq -c '[.rulings[].text]')|$(SA_NOW=$((t0 - 9 * day)) L list | jq -c '[.rulings[].text]')"

# --- the one-time migration applies the owner's list --------------------------
rm -f "$led"
for r in keep drop "cap of 2" "waive bump-guard" unmarked; do SA_NOW=$t0 L ruling "$r" >/dev/null; done
cat > "$tmp/list.json" <<'J'
[{"date": "2025-11-18", "text": "keep", "mark": "pin"},
 {"date": "2025-11-18", "text": "drop", "mark": "lapse"},
 {"date": "2025-11-18", "text": "cap of 2", "mark": "move", "to": "fleet repos.acme/widgets.max_ships"},
 {"date": "2025-11-18", "text": "waive bump-guard", "mark": "move", "to": "ship profile acme/gears: Waivers: bump-guard"}]
J
out=$(SA_NOW=$t0 L migrate-rulings "$tmp/list.json"); rc=$?
check_rc "migrate-rulings exits 0" 0 "$rc"
check "it answers what it pinned, lapsed and moved" '{"pinned":["keep"],"lapsed":["drop","unmarked"],"moved":[{"text":"cap of 2","to":"fleet repos.acme/widgets.max_ships"},{"text":"waive bump-guard","to":"ship profile acme/gears: Waivers: bump-guard"}]}' \
  "$(jq -c '{pinned: [.pinned[].text], lapsed: [.lapsed[].text], moved: [.moved[] | {text, to}]}' <<<"$out")"
check "only the pinned ruling still reads, the same day" '["keep"]' "$(SA_NOW=$t0 L list | jq -c '[.rulings[].text]')"
check "a moved ruling records where it went" "fleet repos.acme/widgets.max_ships" \
  "$(jq -r '.rulings[] | select(.text == "cap of 2") | .moved_to' "$led")"
out=$(SA_NOW=$t0 L migrate-rulings "$tmp/list.json" 2>/dev/null); rc=$?
check_rc "a second migration is refused" 1 "$rc"
check "and says it runs once" 1 "$(jq -r .error <<<"$out" | grep -c 'the migration runs once')"
rm -f "$led"
SA_NOW=$t0 L ruling keep >/dev/null
printf '%s\n' '[{"date": "2025-11-18", "text": "kep", "mark": "pin"}]' > "$tmp/typo.json"
out=$(SA_NOW=$t0 L migrate-rulings "$tmp/typo.json" 2>/dev/null); rc=$?
check_rc "a list naming a ruling the ledger lacks is refused" 1 "$rc"
check "and names the row" 1 "$(jq -r .error <<<"$out" | grep -c 'lacks: 2025-11-18 kep')"
check "and changes nothing" '["keep"]' "$(SA_NOW=$t0 L list | jq -c '[.rulings[].text]')"
printf '%s\n' '[{"date": "2025-11-18", "text": "keep", "mark": "move"}]' > "$tmp/bad.json"
out=$(SA_NOW=$t0 L migrate-rulings "$tmp/bad.json" 2>/dev/null); rc=$?
check_rc "a move naming no destination is a usage error" 2 "$rc"
check "and names the shape it wants" 1 "$(jq -r .error <<<"$out" | grep -c 'a move naming its destination in to')"
printf '%s\n' '{"entries":{},"rulings":[{"text":"no date","allow":[]}]}' > "$led"
out=$(SA_NOW=$t0 L allowed 2>/dev/null); rc=$?
check_rc "a ruling with no date is refused" 2 "$rc"
check "by name, as JSON" 1 "$(jq -r .error <<<"$out" | grep -c 'every ruling needs a date')"

finish
