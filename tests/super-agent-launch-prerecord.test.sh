#!/usr/bin/env bash
# super-agent's record-before-launch, driven through `launch`, `launch record`,
# `ledger` and `reconcile` against the fake `t3` and `gh`: a launch that launches
# writes its ledger entry at stage `launching` (no thread yet) before it prints
# its arguments, `record` binds the thread id to that entry, and `reconcile`
# reports a `launching` entry that never got one, without reading a thread.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-launch-lib.sh
G() { bash "$s/ledger.sh" --ledger "$led" get "$1"; }

# --- launch writes the entry before it answers -------------------------------------------
reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
out=$(L 7 --area skills/widgets --out "$out_f"); rc=$?
check_rc "a launch exits 0" 0 "$rc"
check "the ledger holds the ticket at launching, with no thread or worktree yet" \
  '["launching",null,null,"fix/add-a-frobnicator-to-the-7","home","claudeAgent","opus","high",["skills/widgets"]]' \
  "$(G "$repo#7" | jq -c '[.stage, .thread, .worktree, .branch, .machine, .instance_id, .model, .effort, .areas]')"
L 7 --area skills/widgets --out "$out_f" >/dev/null
check "a launch again (the first turn cut before t3_thread_launch) replaces it: one entry" 1 \
  "$(bash "$s/ledger.sh" --ledger "$led" list | jq '.entries | length')"
issue 9 "widgets: no skill" bug
L 9 >/dev/null 2>&1
check_rc "a launch that does not launch writes no entry" 1 "$(G "$repo#9" >/dev/null 2>&1; echo $?)"

# --- record binds the thread id to it --------------------------------------------------------
sa_thread t-7 running 1 0 /wt/seven fix/add-a-frobnicator-to-the-7
sa_pr $repo fix/add-a-frobnicator-to-the-7 none
out=$(bash "$s/launch.sh" record --launch "$out_f" --thread t-7 --ledger "$led"); rc=$?
check_rc "record exits 0" 0 "$rc"
check "the entry now holds the thread and worktree, and the reconcile moved it on" '["t-7","/wt/seven","running"]' \
  "$(G "$repo#7" | jq -c '[.thread, .worktree, .stage]')"
check "still one entry" 1 "$(bash "$s/ledger.sh" --ledger "$led" list | jq '.entries | length')"

# --- a rethread keeps the open entry: it is already recorded -------------------------------
out=$(L 7 --raise 1 --out "$out_f"); rc=$?
check "a relaunch of an open ticket launches" true "$(jq .launch <<<"$out")"
check "and leaves its entry on the old thread until record --rethread" '["t-7","running"]' "$(G "$repo#7" | jq -c '[.thread, .stage]')"

# --- a task launched with --skill is recorded first too ------------------------------------
reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
sa_skill_file "$repo" .claude/skills/grill-with-artifact/SKILL.md 1.0.0
L 7 --skill grill-with-artifact --out "$out_f" >/dev/null
check "a --skill launch's task entry is at launching" '["launching",null,"task"]' \
  "$(G task:grill-with-artifact-widgets-7 | jq -c '[.stage, .thread, .kind]')"
sa_thread t-g running 1 0 /wt/grill grill-with-artifact/add-a-frobnicator-to-the-7
bash "$s/launch.sh" record --launch "$out_f" --thread t-g --ledger "$led" >/dev/null
check "record binds it" t-g "$(G task:grill-with-artifact-widgets-7 | jq -r .thread)"

# --- reconcile reports a launching entry that never got a thread id ----------------------
reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
L 7 --out "$out_f" >/dev/null
out=$(bash "$s/reconcile.sh" --ledger "$led"); rc=$?
check_rc "reconcile exits 0" 0 "$rc"
check "it names the entry in launching, with when it was written" '[{"key":"acme/widgets#7","since":true}]' \
  "$(jq -c '[.launching[] | {key, since: (.since | type == "string")}]' <<<"$out")"
check "it reads no thread for it: no error, none checked" '{"errors":[],"checked":0}' "$(jq -c '{errors, checked}' <<<"$out")"
check "and leaves it at launching" launching "$(G "$repo#7" | jq -r .stage)"
check "a ledger with none answers an empty list" '[]' "$(rm -f "$led"; bash "$s/reconcile.sh" --ledger "$led" | jq -c .launching)"

finish
