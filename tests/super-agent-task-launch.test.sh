#!/usr/bin/env bash
# super-agent's `launch task` (#1388): a one-off or interactive task launched from the
# owner's ask, driven through its command line over the fake `t3` and `gh`
# (tests/super-agent-fake.sh). A one-off task's message ends with the contract line
# (`sa_task_contract`) and an interactive one's does not; a one-off task takes a slot
# and waits when nothing fits, its waiting row carrying the ask, and an interactive one
# takes none; a task with no repo runs in a scratch folder. No claim and no issue read.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-launch-lib.sh
contract=$(bash -c 'source skills/super-agent/scripts/_lib.sh && printf %s "$sa_task_contract"')
T() { # <slug> [<flags>...]: the task launch on this machine
  local slug=$1; shift
  bash "$s/launch.sh" task "$slug" --fleet "$fleet" --ledger "$led" --quota "$quota" --machine home "$@"
}

check "the contract line asks for a Result: or Needs owner: last line" "yes yes" \
  "$(grep -q '`Result: ' <<<"$contract" && echo yes) $(grep -q '`Needs owner: ' <<<"$contract" && echo yes)"
out=$(bash "$s/launch.sh" --help)
check "--help names the task form" yes "$(grep -q 'launch task <slug> --ask <text>' <<<"$out" && echo yes || echo no)"

# --- a one-off task of a repo -----------------------------------------------------------
reset
out=$(T research-x --ask "Research why the frobnicator stalls" --repo $repo --out "$out_f"); rc=$?
check_rc "a task launch exits 0" 0 "$rc"
check "its message is the ask, the contract line its last line" "$(printf 'Research why the frobnicator stalls\n%s' "$contract")" "$(jq -r .args.message <<<"$out")"
check "the title names the task" "task research-x" "$(jq -r .args.title <<<"$out")"
check "a repo task gets a worktree on task/<slug> from the default branch" \
  '{"type":"worktree","baseRef":"main","branch":"task/research-x","startFromOrigin":true}' "$(jq -c .args.workspaceStrategy <<<"$out")"
check "and needs its project id" '["projectId"]' "$(jq -c .needs <<<"$out")"
check "it is routed as an M" '{"instanceId":"claudeAgent","model":"opus","options":[{"id":"effort","value":"medium"}]}' "$(jq -c .args.modelSelection <<<"$out")"
check "the record is a task entry of the repo" \
  '{"key":"task:research-x","kind":"task","machine":"home","environment_id":null,"repo":"acme/widgets","branch":"task/research-x","interactive":false}' \
  "$(jq -c '.record | {key, kind, machine, environment_id, repo, branch, interactive}' <<<"$out")"
check "the ledger holds it at launching" "launching task" "$(bash "$s/ledger.sh" --ledger "$led" get task:research-x | jq -r '"\(.stage) \(.kind)"')"
check "no claim was posted and no issue read" "0 0" "$(grep -c -- '-X POST' "$SA_FAKE/calls") $(grep -c 'issues' "$SA_FAKE/calls")"
check "--out wrote the answer" "$(jq -c . <<<"$out")" "$(jq -c . "$out_f")"
sa_thread th-x running 0 0 /wt/x task/research-x
out=$(bash "$s/launch.sh" record --launch "$out_f" --thread th-x --ledger "$led"); rc=$?
check_rc "record binds the task's thread" 0 "$rc"
check "its entry is the task's, worktree read from the thread" "task:research-x /wt/x task/research-x" \
  "$(jq -r '.entry | "\(.key) \(.worktree) \(.branch)"' <<<"$out")"

# --- a task with no repo, and a named skill ---------------------------------------------
reset
out=$(T deploy-y --ask "Deploy the dashboard" --skill deploy --out "$out_f"); rc=$?
check_rc "a task with no repo launches" 0 "$rc"
check "it runs in a scratch folder, no worktree" "true false" "$(jq -r '.args | "\(.scratch) \(has("workspaceStrategy"))"' <<<"$out")"
check "and needs nothing an MCP read fills" '[]' "$(jq -c .needs <<<"$out")"
check "--skill opens the message with the skill" "$(printf '/deploy Deploy the dashboard\n%s' "$contract")" "$(jq -r .args.message <<<"$out")"
check "its record has no repo and no branch" "null false" "$(jq -r '.record | "\(.repo) \(has("branch"))"' <<<"$out")"
sa_thread th-y running 0 0 '' ''
out=$(bash "$s/launch.sh" record --launch "$out_f" --thread th-y --ledger "$led"); rc=$?
check_rc "record binds a scratch task with no worktree" 0 "$rc"
check "its entry holds the thread" th-y "$(bash "$s/ledger.sh" --ledger "$led" get task:deploy-y | jq -r .thread)"
out=$(T z --ask x --area skills/x 2>/dev/null); rc=$?
check_rc "--area with no repo is a usage error" 2 "$rc"
out=$(T 'a/b' --ask x 2>/dev/null); rc=$?
check_rc "a slug outside the ledger's charset is a usage error" 2 "$rc"

# --- slots: a one-off task takes one, an interactive one none -----------------------------
reset
jq '.machines = {home: {cores: 8, slots: 1, max_load: 8, gh_logins: ["alice"]}}' "$fleet" > "$tmp/one.json"
F() { local slug=$1; shift; bash "$s/launch.sh" task "$slug" --fleet "$tmp/one.json" --ledger "$led" --quota "$quota" --machine home "$@"; }
out=$(F grill-a --ask "Grill me on the cache" --skill grill-with-artifact); rc=$?
check_rc "an interactive task launches" 0 "$rc"
check "its message is the skill call alone, no contract line" "/grill-with-artifact Grill me on the cache" "$(jq -r .args.message <<<"$out")"
check "it is recorded interactive, on this machine" "true home null" "$(jq -r '.record | "\(.interactive) \(.machine) \(.environment_id)"' <<<"$out")"
out=$(F one-a --ask "Run the benchmark"); rc=$?
check_rc "the interactive task filled no slot: a one-off task still fits" 0 "$rc"
out=$(F one-b --ask "Run the soak test" --repo $repo); rc=$?
check_rc "the one-off task took the only slot: the next one waits" 1 "$rc"
check "it answers waiting" waiting "$(jq -r .reason <<<"$out")"
check "the waiting row carries the ask and the repo" "Run the soak test acme/widgets" \
  "$(bash "$s/ledger.sh" --ledger "$led" list | jq -r '.waiting[] | select(.key == "task:one-b") | "\(.ask) \(.repo)"')"
out=$(F grill-b --ask "Grill me on the queue" --interactive); rc=$?
check_rc "an interactive task launches on a full machine" 0 "$rc"
rm -f "$SA_FAKE/calls"
out=$(bash "$s/reconcile.sh" --ledger "$led")
check "reconcile lists the waiting task ready, with its ask" "task:one-b Run the soak test" "$(jq -r '.ready[] | "\(.key) \(.ask)"' <<<"$out")"
check "and reads no issue for it" 0 "$(grep -c 'issues' "$SA_FAKE/calls")"

# --- a waiting row keeps the place flags its relaunch re-passes -----------------------------
out=$(F one-c --ask "Train the model" --repo $repo --gpu --account alice --area skills/x --exclude box); rc=$?
check_rc "a task with place flags waits on the full machine" 1 "$rc"
check "its row keeps --gpu, --account, --area and --exclude" '{"gpu":true,"account":"alice","areas":["skills/x"],"exclude":["box"]}' \
  "$(bash "$s/ledger.sh" --ledger "$led" list | jq -c '.waiting[] | select(.key == "task:one-c") | {gpu, account, areas, exclude}')"
check "a row with none keeps no place field" '[]' \
  "$(bash "$s/ledger.sh" --ledger "$led" list | jq -c '.waiting[] | select(.key == "task:one-b") | [keys[] | select(IN("gpu", "account", "areas", "exclude"))]')"
check "reconcile lists the row ready with its place flags" '{"gpu":true,"account":"alice","areas":["skills/x"],"exclude":["box"]}' \
  "$(bash "$s/reconcile.sh" --ledger "$led" | jq -c '.ready[] | select(.key == "task:one-c") | {gpu, account, areas, exclude}')"
check "and a row with none lists no place field" '[]' \
  "$(bash "$s/reconcile.sh" --ledger "$led" | jq -c '.ready[] | select(.key == "task:one-b") | [keys[] | select(IN("gpu", "account", "areas", "exclude"))]')"
check "a ticket's row takes no place flag" 2 "$(bash "$s/ledger.sh" --ledger "$led" wait "$repo#9" --reason full --gpu >/dev/null 2>&1; echo $?)"

# --- the stall ladder's rung 3: a task relaunched with --raise, recorded --rethread -----------
reset
T research-x --ask "Research the stall" --repo $repo --out "$out_f" >/dev/null
sa_thread th-x running 0 0 /wt/x task/research-x
bash "$s/launch.sh" record --launch "$out_f" --thread th-x --ledger "$led" >/dev/null
out=$(T research-x --ask "Research the stall" --repo $repo 2>/dev/null); rc=$?
check_rc "an open task's slug launches again only with --raise" 2 "$rc"
out=$(T research-x --ask "Research the stall" --repo $repo --raise 1 --out "$out_f"); rc=$?
check_rc "--raise relaunches the open task" 0 "$rc"
check "and leaves its entry on the old thread until record --rethread" th-x \
  "$(bash "$s/ledger.sh" --ledger "$led" get task:research-x | jq -r .thread)"
sa_thread th-x2 running 0 0 /wt/x2 task/research-x
out=$(bash "$s/launch.sh" record --launch "$out_f" --thread th-x2 --ledger "$led" --rethread); rc=$?
check_rc "record --rethread binds the new thread" 0 "$rc"
check "the entry is the same task's, on the new thread" "th-x2 /wt/x2 1" \
  "$(bash "$s/ledger.sh" --ledger "$led" get task:research-x | jq -r '"\(.thread) \(.worktree) \(.stalls == 0 | if . then 1 else 0 end)"')"
T deploy-y --ask "Deploy the dashboard" --out "$out_f" >/dev/null
sa_thread th-y running 0 0 '' ''
bash "$s/launch.sh" record --launch "$out_f" --thread th-y --ledger "$led" >/dev/null
T deploy-y --ask "Deploy the dashboard" --raise 1 --out "$out_f" >/dev/null
sa_thread th-y2 running 0 0 '' ''
out=$(bash "$s/launch.sh" record --launch "$out_f" --thread th-y2 --ledger "$led" --rethread); rc=$?
check_rc "a scratch task rethreads too" 0 "$rc"
check "onto the new thread" th-y2 "$(bash "$s/ledger.sh" --ledger "$led" get task:deploy-y | jq -r .thread)"

# --- a ticket run with a named one-off skill ends on the contract line -----------------------
reset; issue 7 "widgets: add a frobnicator" ready-for-agent
sa_skill_file "$repo" .claude/skills/research/SKILL.md 1.0.0
out=$(bash "$s/launch.sh" "$repo#7" --fleet "$fleet" --ledger "$led" --quota "$quota" --machine home --thread th-super \
  --skill research --note "Mind the cache."); rc=$?
check_rc "a ticket-form --skill task launches" 0 "$rc"
check "its message is the skill call and the note, the contract line its last line" \
  "$(printf '/research 7\nNote: Mind the cache.\n%s' "$contract")" "$(jq -r .args.message <<<"$out")"
reset; issue 7 "widgets: add a frobnicator" ready-for-agent
sa_skill_file "$repo" .claude/skills/grill-with-artifact/SKILL.md 1.0.0
out=$(bash "$s/launch.sh" "$repo#7" --fleet "$fleet" --ledger "$led" --quota "$quota" --machine home --thread th-super --skill grill-with-artifact)
check "a ticket-form grill carries no contract line" "/grill-with-artifact 7" "$(jq -r .args.message <<<"$out")"

# --- one slug check: a slug starting with . is refused everywhere -----------------------------
reset
check "launch task refuses a .slug" 2 "$(T .x --ask x >/dev/null 2>&1; echo $?)"
check "ledger add refuses a .slug" 2 "$(bash "$s/ledger.sh" --ledger "$led" add --task .x --thread t >/dev/null 2>&1; echo $?)"
check "ledger wait refuses a .slug" 2 "$(bash "$s/ledger.sh" --ledger "$led" wait task:.x --reason full --ask x >/dev/null 2>&1; echo $?)"

finish
