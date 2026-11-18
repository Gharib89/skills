#!/usr/bin/env bash
# super-agent's owner overrides (#1279), driven through the command lines over the
# fake `t3` and `gh` (tests/super-agent-fake.sh): `launch --owner-go` past the floors
# and the reserve, `launch --skill <name>` and the interactive entry it records, the
# ledger's `pause`, `unpause`, `drop` and `reset-stalls`, and what reconcile, watch,
# placement and the status block do with a paused entry.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
extra=$(command -v sleep ln setsid)
source tests/super-agent-launch-lib.sh
for t in $extra; do "$tmp/tools/ln" -s "$t" "$tmp/tools/" 2>/dev/null || /bin/ln -s "$t" "$tmp/tools/" || exit 2; done
mkdir -p "$SA_FAKE/threads" "$tmp/home"
export HOME=$tmp/home
LG() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
R() { bash "$s/reconcile.sh" --ledger "$led"; }
low5h() { # a quota whose only instance sits under the 5 hour floor
  jq -cn '{providers: {claudeAgent: {driver: "claude", status: "available", auth: "ok",
    buckets: [{id: "week", window: "weekly", remaining: 0.8}, {id: "five", window: "5h", remaining: 0.05}]}}}' > "$quota"
}
ship_entry() { # <n> <thread>: a ship entry on home, its thread at rest after one run
  LG add --repo $repo --number "$1" --thread "$2" --worktree "/wt/$1" --branch "feat/x-$1" --machine home >/dev/null
  sa_thread "$2" idle 1 0 "/wt/$1" "feat/x-$1"; sa_pr $repo "feat/x-$1" none; sa_issue $repo "$1" open
}

# --- --owner-go launches below the floors and records a ruling -------------------------
reset; issue 7 "widgets: a ticket" ready-for-agent S; low5h
out=$(L 7); rc=$?
check "below the 5 hour floor a launch has no instance" "1 no_instance" "$rc $(jq -r .reason <<<"$out")"
out=$(L 7 --owner-go --out "$out_f"); rc=$?
check_rc "with --owner-go it launches" 0 "$rc"
check "on the floored instance, the answer saying the go was used" "claudeAgent true" \
  "$(jq -r '"\(.args.modelSelection.instanceId) \(.record.owner_go)"' <<<"$out")"
owner_go_rulings() { LG list | jq '[.rulings[] | select((.text | contains("--owner-go")) and (.text | contains("acme/widgets#7")))] | length'; }
check "the launch call alone writes no ruling" 0 "$(owner_go_rulings)"
br=$(jq -r .args.workspaceStrategy.branch "$out_f"); sa_thread th-7 running 1 0 /wt/7 "$br"; sa_pr $repo "$br" none
bash "$s/launch.sh" record --launch "$out_f" --thread th-7 --ledger "$led" >/dev/null
check "its record writes a ruling naming the override and the ticket" 1 "$(owner_go_rulings)"
jq '.providers.claudeAgent.buckets[0].remaining = 0.01' "$quota" > "$tmp/q2.json"
check "--owner-go also passes the weekly reserve" claudeAgent "$(L 7 --owner-go --quota "$tmp/q2.json" | jq -r .args.modelSelection.instanceId)"
jq '.providers.claudeAgent.buckets[0].remaining = 0' "$quota" > "$tmp/q3.json"
check "an empty weekly bucket still has no instance" no_instance "$(L 7 --owner-go --quota "$tmp/q3.json" | jq -r .reason)"
check "route reads --owner-go too" claudeAgent "$(bash "$s/route.sh" --size S --quota "$quota" --owner-go | jq -r .instance_id)"
jq -cn '{providers: {a: {driver: "claude", auth: "ok", buckets: [{id: "week", window: "weekly", remaining: 0.9}, {id: "five", window: "5h", remaining: 0}]},
  b: {driver: "claude", auth: "ok", buckets: [{id: "week", window: "weekly", remaining: 0.5}, {id: "five", window: "5h", remaining: 0.8}]}}}' > "$tmp/q4.json"
check "with an instance inside the floors, --owner-go is not used and routes as without it" "b false" \
  "$(bash "$s/route.sh" --size S --quota "$tmp/q4.json" --owner-go | jq -r '"\(.instance_id) \(.owner_go)"')"
jq '.providers.cur = {driver: "cursor", auth: "ok", route: true, buckets: []}' "$quota" > "$tmp/q5.json"
check "a last-resort instance does not stand in for the go" "claudeAgent true" \
  "$(bash "$s/route.sh" --size S --quota "$tmp/q5.json" --owner-go | jq -r '"\(.instance_id) \(.owner_go)"')"

# --- --skill launches a named skill; an interactive entry gets no stall -----------------
reset; issue 9 "widgets: settle the design" enhancement
check "without an owner-skill label there is no launch" no_owner_skill "$(L 9 | jq -r .reason)"
out=$(L 9 --skill grill-with-artifact); rc=$?
check "a skill installed nowhere is refused before the claim" "1 no_skill 0" \
  "$rc $(jq -r .reason <<<"$out") $(grep -c -- '-X POST' "$SA_FAKE/calls")"
sa_skill_file "$repo" .claude/skills/grill-with-artifact/SKILL.md 1.0.0
out=$(L 9 --skill grill-with-artifact --out "$out_f"); rc=$?
check_rc "a skill the repo installs launches" 0 "$rc"
check "its message invokes the skill on the ticket" "/grill-with-artifact 9" "$(jq -r .args.message <<<"$out")"
check "it records a task entry for the skill and the repo, interactive" '{"key":"task:grill-with-artifact-widgets-9","kind":"task","interactive":true}' \
  "$(jq -c '.record | {key, kind, interactive}' <<<"$out")"
mkdir -p "$HOME/.claude/skills/to-tickets"; printf -- '---\nname: to-tickets\n---\n' > "$HOME/.claude/skills/to-tickets/SKILL.md"
check "a personal skill counts as installed, and is not interactive" "true false" \
  "$(L 9 --skill to-tickets | jq -r '[.launch, .record.interactive] | map(tostring) | join(" ")')"
check "--skill ship launches a ship whatever the labels" "ship /ship 9" "$(L 9 --skill ship | jq -r '"\(.kind) \(.args.message)"')"
check "a skill name opening on a dot is refused" 2 "$(L 9 --skill .. >/dev/null 2>&1; echo $?)"
sa_gh_fail contents/.claude/skills/to-tickets 1
check "a failed read of the repo's skill is no verdict" 2 "$(L 9 --skill to-tickets >/dev/null 2>&1; echo $?)"
jq '.machines.home.slots = 0' "$fleet" > "$tmp/fleet0.json"
F0() { bash "$s/launch.sh" "$repo#9" --fleet "$tmp/fleet0.json" --ledger "$led" --quota "$quota" --machine home --thread th-super --readings "$readings" "$@"; }
check "a repo skill goes to another machine when this one is full" env-box "$(F0 --skill grill-with-artifact | jq -r .args.environmentId)"
check "a skill only this machine installs waits for this machine" waiting "$(F0 --skill to-tickets | jq -r .reason)"
sa_thread th-g running 1 0 /wt/g "$(jq -r .args.workspaceStrategy.branch "$out_f")"
sa_pr $repo "$(jq -r .args.workspaceStrategy.branch "$out_f")" none
out=$(bash "$s/launch.sh" record --launch "$out_f" --thread th-g --ledger "$led"); rc=$?
check_rc "record writes the skill's entry" 0 "$rc"
check "the entry is interactive, keyed by the skill and the ticket" "task:grill-with-artifact-widgets-9 true acme/widgets" \
  "$(LG get task:grill-with-artifact-widgets-9 | jq -r '[.key, (.interactive | tostring), .repo] | join(" ")')"
sa_thread th-g idle 2 0 /wt/g "$(jq -r .args.workspaceStrategy.branch "$out_f")"
out=$(R)
check "an interactive entry at rest after a run is not settled and not stalled" "at-rest 0 0" \
  "$(jq -r '[(.entries[] | select(.key == "task:grill-with-artifact-widgets-9") | .stage), (.stalled | length), (.settled | length)] | map(tostring) | join(" ")' <<<"$out")"
LG set task:grill-with-artifact-widgets-9 rest_since '"2020-01-01T00:00:00Z"' >/dev/null
out=$(R)
check "nor past the stall window" "0 0" "$(jq -r '[(.stalled | length), (.escalate | length)] | map(tostring) | join(" ")' <<<"$out")"
check "its count stays 0" 0 "$(LG get task:grill-with-artifact-widgets-9 | jq -r .stalls)"
out=$(bash "$s/watch.sh" --ledger "$led" --interval 1 --recheck 0 --timeout 2 --stall-window 1)
check "the watcher raises no stall-window for it" timeout "$(jq -r .event <<<"$out")"
out=$(bash "$s/launch.sh" record --task grill-plan --thread th-gp --ledger "$led" --worktree /wt/gp --interactive); rc=$?
check "record --task --interactive records an interactive task" "0 true" "$rc $(LG get task:grill-plan | jq -r .interactive)"
check "a ticket entry cannot be interactive" 2 "$(LG add --repo $repo --number 40 --thread th-40 --worktree /wt/40 --branch b --machine home --interactive >/dev/null 2>&1; echo $?)"

# --- a paused entry: no stall, no nudge row, still a slot --------------------------------
reset; mkdir -p "$SA_FAKE/threads"
ship_entry 20 th-20
R >/dev/null
out=$(LG pause $repo#20); rc=$?
check "pause marks the entry" "0 true" "$rc $(LG get $repo#20 | jq -r .paused)"
check "pause of a key not in the ledger exits 1" 1 "$(LG pause $repo#99 >/dev/null 2>&1; echo $?)"
LG set $repo#20 rest_since '"2020-01-01T00:00:00Z"' >/dev/null
sa_thread th-20 idle 4 1 /wt/20 feat/x-20
out=$(R)
check "a paused entry counts no stall and holds no nudge or escalate row" "0 0 0 0" \
  "$(jq -r '[(.stalled | length), (.escalate | length), (.at_rest | length), (.settled | length)] | map(tostring) | join(" ")' <<<"$out")"
check "its count stays 0" 0 "$(LG get $repo#20 | jq -r .stalls)"
out=$(bash "$s/watch.sh" --ledger "$led" --interval 1 --recheck 0 --timeout 2 --stall-window 1)
check "the watcher wakes on nothing for it" timeout "$(jq -r .event <<<"$out")"
out=$(bash "$s/status.sh" --ledger "$led" --digest)
check "the Running row marks it paused" 1 "$(jq -r .block <<<"$out" | grep -c 'widgets#20.*(paused)')"
jq '.machines.home.slots = 1 | .machines.home.reserve = 0' "$fleet" > "$tmp/fleet1.json"
issue 21 "widgets: next" ready-for-agent S
out=$(bash "$s/launch.sh" "$repo#21" --fleet "$tmp/fleet1.json" --ledger "$led" --quota "$quota" --machine home --thread th-super --exclude box)
check "it still takes its machine's slot" waiting "$(jq -r .reason <<<"$out")"

# --- unpause restarts watching from the thread's current state ---------------------------
out=$(LG unpause $repo#20); rc=$?
check "unpause clears the mark and the baseline" "0 false null" "$rc $(LG get $repo#20 | jq -r '[(.paused | tostring), (.observed | tostring)] | join(" ")')"
sa_thread th-20 idle 6 0 /wt/20 feat/x-20
R >/dev/null; out=$(R)
check "the owner's runs count no stall after the give-back" "0 0" "$(jq -r '[(.stalled | length)] | map(tostring) | join(" ")' <<<"$out") $(LG get $repo#20 | jq -r .stalls)"
sa_thread th-20 idle 7 0 /wt/20 feat/x-20
check "a run after the give-back counts as before" 1 "$(R | jq '.stalled | length')"

# --- a paused ticket settles on GitHub alone; a paused task stays until drop -------------
LG pause $repo#20 >/dev/null
rm -f "$SA_FAKE/threads/th-20.json"
sa_pr $repo feat/x-20 merged
out=$(R)
check "a paused entry whose PR merged settles, its thread unread" "settled 0" \
  "$(LG get $repo#20 | jq -r .stage) $(jq '.errors | length' <<<"$out")"
check "with no cleanup owed" "0 0 null" "$(jq -r '[(.cleanup | length), (.settled | length)] | map(tostring) | join(" ")' <<<"$out") $(LG get $repo#20 | jq -r '.cleanup_owed | tostring')"
ship_entry 22 th-22; R >/dev/null; LG pause $repo#22 >/dev/null
sa_issue $repo 22 closed
R >/dev/null
check "a paused entry whose issue closed settles with no cleanup owed" "settled null" "$(LG get $repo#22 | jq -r '"\(.stage) \(.cleanup_owed | tostring)"')"
check "unpause of a paused entry that ended exits 1, its baseline kept" "1 false" \
  "$(LG unpause $repo#22 >/dev/null 2>&1; echo $?) $(LG get $repo#22 | jq -r '.observed == null')"
LG add --repo $repo --number 23 --kind triage --thread th-23 --worktree /wt/23 --branch triage/x-23 --machine home >/dev/null
sa_thread th-23 idle 1 0 /wt/23 triage/x-23; sa_pr $repo triage/x-23 none; sa_issue $repo 23 open needs-triage
R >/dev/null; LG pause $repo#23 >/dev/null; sa_issue $repo 23 closed; R >/dev/null
sa_thread th-23 idle 3 0 /wt/23 triage/x-23
check "a paused triage entry that settled is not read again" "settled 0" "$(LG get $repo#23 | jq -r .stage) $(R | jq '.woke | length')"
LG add --task deploy --thread th-d --worktree /wt/d --machine home >/dev/null
sa_thread th-d running 1 0 /wt/d x; R >/dev/null
LG pause task:deploy >/dev/null
sa_thread th-d idle 1 0 /wt/d x
R >/dev/null
check "a paused task at rest stays open" running "$(LG get task:deploy | jq -r .stage)"
check "the Running row marks a paused task too" 1 "$(bash "$s/status.sh" --ledger "$led" --digest | jq -r .block | grep -c 'task:deploy.*(paused)')"
out=$(LG drop task:deploy); rc=$?
check "drop removes it" "0 true" "$rc $(jq -r .removed <<<"$out")"
check "and the ledger no longer holds it" 1 "$(LG get task:deploy >/dev/null 2>&1; echo $?)"
check "drop of a key not in the ledger exits 1" 1 "$(LG drop task:deploy >/dev/null 2>&1; echo $?)"

# --- reset-stalls zeroes the count and records it ----------------------------------------
ship_entry 30 th-30; R >/dev/null
LG set $repo#30 stalls 3 >/dev/null
out=$(LG reset-stalls $repo#30); rc=$?
check_rc "reset-stalls exits 0" 0 "$rc"
check "it zeroes the count" 0 "$(LG get $repo#30 | jq -r .stalls)"
check "and leaves a ruling naming the key and the old count" 1 \
  "$(LG list | jq '[.rulings[] | select((.text | contains("acme/widgets#30")) and (.text | contains("3")) and (.text | contains("reset-stalls")))] | length')"
check "reset-stalls of a key not in the ledger exits 1" 1 "$(LG reset-stalls $repo#98 >/dev/null 2>&1; echo $?)"
ship_entry 31 th-31; R >/dev/null
check "unpause of an entry not paused exits 1, its baseline kept" "1 false" \
  "$(LG unpause $repo#31 >/dev/null 2>&1; echo $?) $(LG get $repo#31 | jq -r '.observed == null')"
sa_pr $repo feat/x-30 merged; R >/dev/null
check "reset-stalls of an entry that ended exits 1" "settled 1" "$(LG get $repo#30 | jq -r .stage) $(LG reset-stalls $repo#30 >/dev/null 2>&1; echo $?)"

finish
