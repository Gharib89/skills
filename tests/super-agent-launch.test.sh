#!/usr/bin/env bash
# super-agent's `launch` and `launch record`, driven through their command lines
# over the fake `t3` and `gh` (tests/super-agent-fake.sh): the launch call prints the
# whole `t3_thread_launch` argument object built from the claim, the saved quota
# read, the route, the placement and the brief, or names why it did not launch
# (each reason, no argument object); `record` writes the ledger entry with the
# fleet's machine key and the routed tier's model and effort, then reconciles. The
# end of the file runs launch, record, reconcile and status in a row.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/fake" "$tmp/remote"
for t in bash env jq awk sed grep cat mktemp mv rm mkdir dirname basename tr head tail date timeout sort cut find wc diff chmod cp; do
  ln -s "$(command -v $t)" "$tmp/tools/$t" || exit 2
done
export PATH="$tmp/bin:$tmp/tools" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
fleet=$tmp/fleet.json led=$tmp/ledger.json quota=$tmp/quota.json readings=$tmp/readings.json out_f=$tmp/launch.json
repo=acme/widgets
cat > "$fleet" <<'JSON'
{"thread_ram_floor_gb": 4,
 "machines": {"home": {"cores": 8, "slots": 4, "reserve": 1, "max_load": 8, "gpu": null, "gh_logins": ["alice"], "brief": ["Machine line: the home box has one GPU shared by all runs."]},
              "box": {"environment_id": "env-box", "cores": 8, "slots": 4, "max_load": 8, "gpu": null, "gh_logins": ["alice"]}},
 "repos": {"acme/widgets": {"max_ships": 2, "brief": ["Repo line: run the widget suite with `make test`."]}},
 "waivers": [{"id": "w", "condition": "Codex answers with a usage-limit notice: record it as not landed."}]}
JSON
quota_with() { # <weekly remaining> [<auth>]
  jq -cn --argjson w "$1" --arg a "${2:-ok}" '{providers: {claudeAgent: {driver: "claude", status: "available", auth: $a,
    buckets: [{id: "week", window: "weekly", remaining: $w}, {id: "five", window: "5h", remaining: 0.9}]}}}' > "$quota"
}
issue() { # <number> <title> <label>...
  local n=$1 t=$2; shift 2
  sa_route "repos/$repo/issues/$n" "$(jq -cn --arg t "$t" --argjson n "$n" '{number: $n, title: $t, state: "open", labels: ($ARGS.positional | map({name: .}))}' --args "$@")"
  sa_route "repos/$repo/issues/$n/comments" '[]'
}
L() { # <number> [<launch flags>...]: the launch call for one ticket of the repo
  local n=$1; shift
  bash "$s/launch.sh" "$repo#$n" --fleet "$fleet" --ledger "$led" --quota "$quota" --machine home --thread th-super "$@"
}
reset() {
  rm -f "$led" "$SA_FAKE/calls" "$SA_FAKE/on-post" "$out_f"
  sa_machine home 8 16384; sa_load 0.5 12288; sa_environments '[{"environmentId":"env-box","label":"box","status":"reachable"}]'
  sa_route user '{"login":"octo"}'; sa_route "repos/$repo" '{"default_branch":"main"}'
  echo 2026-11-06T12:00:00Z > "$SA_FAKE/now"
  quota_with 0.8
  printf '{"box":{"load1":1,"free_gb":20}}\n' > "$readings"
}

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/launch.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: launch" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/launch.sh" --bogus 2>/dev/null); rc=$?
check "a bad key answers the usage line" "$(sed -n 1p <<<"$(bash "$s/launch.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad key exits 2" 2 "$rc"
reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
check_rc "a missing flag exits 2" 2 "$(bash "$s/launch.sh" "$repo#7" --fleet "$fleet" --ledger "$led" >/dev/null 2>&1; echo $?)"
check_rc "a wanted answer that is neither yes nor no exits 2" 2 "$(L 7 --wanted maybe >/dev/null 2>&1; echo $?)"
check_rc "a raise that is no number exits 2" 2 "$(L 7 --raise x >/dev/null 2>&1; echo $?)"
check_rc "record with no launch file and no task is an unrecorded launch, exit 1" 1 "$(bash "$s/launch.sh" record --thread t --ledger "$led" >/dev/null 2>&1; echo $?)"
check_rc "record with a launch file that is not there exits 2" 2 "$(bash "$s/launch.sh" record --launch "$tmp/none.json" --thread t --ledger "$led" >/dev/null 2>&1; echo $?)"

# --- a ready ticket: the whole argument object ----------------------------------
reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
out=$(L 7 --area skills/widgets --note "Mind the flaky test." --out "$out_f"); rc=$?
check_rc "a launch exits 0" 0 "$rc"
check "it launches a ship of the labelled size, on a fresh claim" '{"launch":true,"kind":"ship","size":"L","size_source":"label","claim":"taken"}' \
  "$(jq -c '{launch, kind, size, size_source, claim}' <<<"$out")"
check "the title is the repo and the slug" "widgets#7 add-a-frobnicator-to-the" "$(jq -r .args.title <<<"$out")"
check "the worktree strategy names the base and the branch /ship would" \
  '{"type":"worktree","baseRef":"main","branch":"fix/add-a-frobnicator-to-the-7","startFromOrigin":true}' "$(jq -c .args.workspaceStrategy <<<"$out")"
check "L starts on the third rung, on route's instance, options an array" \
  '{"instanceId":"claudeAgent","model":"opus","options":[{"id":"effort","value":"high"}]}' "$(jq -c .args.modelSelection <<<"$out")"
check "a local launch carries no environment id" false "$(jq '.args | has("environmentId")' <<<"$out")"
check "the message opens with the owner-skill invocation" "/ship 7" "$(jq -r .args.message <<<"$out" | sed -n 1p)"
check "then the brief, waiver word for word" 1 "$(jq -r .args.message <<<"$out" | grep -cF 'Codex answers with a usage-limit notice: record it as not landed.')"
check "the brief carries the repo's cap-scoped line, the machine's line and the note" 3 \
  "$(jq -r .args.message <<<"$out" | grep -cE '^  (Repo line: run the widget|Machine line: the home box|Mind the flaky)')"
check "the argument only an MCP read fills is named" '["projectId"]' "$(jq -c .needs <<<"$out")"
check "the record block holds what the ledger will carry" \
  '{"key":"acme/widgets#7","kind":"ship","machine":"home","environment_id":null,"instance_id":"claudeAgent","model":"opus","effort":"high","areas":["skills/widgets"],"branch":"fix/add-a-frobnicator-to-the-7"}' "$(jq -c .record <<<"$out")"
check "--out wrote the same answer" "$(jq -c . <<<"$out")" "$(jq -c . "$out_f")"
check "the claim comment was posted" 1 "$(grep -c -- '-X POST' "$SA_FAKE/calls")"
check "and nothing was assigned" 0 "$(grep -c 'assignees' "$SA_FAKE/calls")"
issue 13 "widgets: tidy the pipeline" ready-for-agent S refactor
check "a refactor ticket branches as refactor, the type its label names" "refactor/tidy-the-pipeline-13" "$(L 13 --area skills/widgets | jq -r .args.workspaceStrategy.branch)"
issue 14 "widgets: bump a tool" ready-for-agent S chore
check "a chore ticket branches as chore" "chore/bump-a-tool-14" "$(L 14 --area skills/widgets | jq -r .args.workspaceStrategy.branch)"

jq '.providers.claudeAgent.models = {opus: "claude-opus-5-5"}' "$quota" > "$tmp/qm.json"
reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
check "the exact id the fleet entry maps for the tier rides into modelSelection" claude-opus-5-5 \
  "$(L 7 --area skills/widgets --quota "$tmp/qm.json" | jq -r .args.modelSelection.model)"

# --- a triage ticket with no Size label ------------------------------------------
issue 11 "Something is off" needs-triage
out=$(L 11)
check "a needs-triage ticket takes /triage, a triage/ branch and the default size M" '["/triage 11","triage/something-is-off-11","M","default"]' \
  "$(jq -c '[(.args.message | split("\n")[0]), .args.workspaceStrategy.branch, .size, .size_source]' <<<"$out")"

# --- the flags place and route take pass through -------------------------------------
sa_load 9 12288
out=$(L 7); rc=$?
check_rc "own machine over its load limit and the other unread: no launch, exit 1" 1 "$rc"
check "the reason is need_reading, naming the machine to probe" '{"launch":false,"reason":"need_reading","detail":{"machine":"box","environment_id":"env-box"}}' \
  "$(jq -c '{launch, reason, detail}' <<<"$out")"
out=$(L 7 --readings "$readings" --account alice)
check "with its reading it launches on the linked machine, carrying the environment id" '["env-box","box"]' \
  "$(jq -c '[.args.environmentId, .record.machine]' <<<"$out")"
check "a named instance the quota read lacks is no_instance" no_instance "$(L 7 --readings "$readings" --instance ghost | jq -r .reason)"
sa_load 0.5 12288
check "a gh login no machine holds is waiting, with the machines considered" '["waiting",2]' "$(L 7 --account nobody | jq -c '[.reason, (.detail.considered | length)]')"

# --- each reason it does not launch, with no argument object ---------------------------
reset
issue 8 "A ticket with no owner skill" needs-info
out=$(L 8); rc=$?
check "no owner skill: exit 1, the reason and the labels" '{"launch":false,"reason":"no_owner_skill","detail":["needs-info"]}' "$(jq -c '{launch, reason, detail}' <<<"$out")"
check_rc "it exits 1" 1 "$rc"
check "and it posted no claim" 0 "$(grep -c -- '-X POST' "$SA_FAKE/calls")"

issue 9 "Held elsewhere" ready-for-agent M
sa_route "repos/$repo/issues/9/comments" "$(jq -cn '[{id: 5, created_at: "2099-01-01T00:00:00Z", user: {login: "octo"}, body: "<!-- super-agent-claim machine=other thread=th-o -->\nClaimed."}]')"
out=$(L 9)
check "a fresh claim of another machine is claimed" '{"launch":false,"reason":"claimed","machine":"other"}' "$(jq -c '{launch, reason, machine: .detail.machine}' <<<"$out")"
check "and no argument object is printed" false "$(jq 'has("args")' <<<"$out")"
sa_route "repos/$repo/issues/9/comments" "$(jq -cn '[{id: 5, created_at: "2026-10-01T11:00:00Z", user: {login: "octo"}, body: "<!-- super-agent-claim machine=other thread=th-o -->\nClaimed."}]')"
check "a claim past the stale window is stale" stale "$(L 9 | jq -r .reason)"

issue 12 "Owner decides" ready-for-agent S
quota_with 0.3
out=$(L 12 --raise 1)
check "a raise the quota cannot afford asks, with the wanted tier and no argument object" '{"launch":false,"reason":"ask","wanted":"opus","tier":"sonnet","args":false}' \
  "$(jq -c '{launch, reason, wanted: .detail.wanted.model, tier: .detail.tier.model, args: has("args")}' <<<"$out")"
check "--wanted yes launches the wanted tier" '{"model":"opus","effort":"medium"}' "$(L 12 --raise 1 --wanted yes | jq -c '{model: .args.modelSelection.model, effort: .args.modelSelection.options[0].value}')"
check "--wanted no launches the default tier" '{"model":"sonnet","effort":"medium"}' "$(L 12 --raise 1 --wanted no | jq -c '{model: .args.modelSelection.model, effort: .args.modelSelection.options[0].value}')"
check "the ledger entry for it carries the tier launched" '{"model":"opus","effort":"medium"}' "$(L 12 --raise 1 --wanted yes | jq -c '.record | {model, effort}')"

quota_with 0.8 failed
check "no instance able to launch is no_instance, with route's reason" no_instance "$(L 7 | jq -r .reason)"
echo stale > "$out_f"; L 7 --out "$out_f" >/dev/null
check "an answer that does not launch removes a stale --out file" absent "$([ -e "$out_f" ] && echo present || echo absent)"
quota_with 0.8

# --- a brief that cannot be built is no launch --------------------------------------
reset; issue 7 "widgets: add a frobnicator" ready-for-agent S
jq '.repos = {"acme/widgets": {"brief": "one line"}}' "$fleet" > "$tmp/badfleet.json"
out=$(bash "$s/launch.sh" "$repo#7" --fleet "$tmp/badfleet.json" --ledger "$led" --quota "$quota" --machine home --thread th-super --area x 2>&1); rc=$?
check "a fleet whose brief lines are mis-shaped exits 2, never launching with an empty brief" "2 false" "$rc $(jq -r 'has("args")' <<<"$out")"
for stub in brief route; do
  rm -rf "$tmp/stub"; cp -r "$s" "$tmp/stub"; printf 'exit 0\n' > "$tmp/stub/$stub.sh"
  out=$(bash "$tmp/stub/launch.sh" "$repo#7" --fleet "$fleet" --ledger "$led" --quota "$quota" --machine home --thread th-super --area x 2>&1); rc=$?
  check "a $stub that prints nothing exits 2 with a named error, never launching" "2 false $stub gave no answer" "$rc $(jq -r 'has("args")' <<<"$out") $(jq -r .error <<<"$out")"
done
reset

# --- the per-repo cap: a launch over it is a waiting row -----------------------------
bash "$s/ledger.sh" --ledger "$led" add --repo $repo --number 1 --thread t1 --worktree /w/1 --branch b1 --machine home --area a >/dev/null
bash "$s/ledger.sh" --ledger "$led" add --repo $repo --number 2 --thread t2 --worktree /w/2 --branch b2 --machine home --area b --kind triage >/dev/null
out=$(L 7 --area c); rc=$?
check_rc "with the repo's two open tickets (ship and triage) at its cap of 2 the launch exits 1" 1 "$rc"
check "it is waiting, the cap named in the reason" '{"reason":"waiting","why":"ship cap: 2 of 2 open tickets of acme/widgets"}' "$(jq -c '{reason, why: .detail.reason}' <<<"$out")"
check "a launch with no area, which overlaps both, still names the cap first" "ship cap: 2 of 2 open tickets of acme/widgets" "$(L 7 | jq -r .detail.reason)"
check "and the ledger holds the waiting row" 1 "$(bash "$s/ledger.sh" --ledger "$led" list | jq '[.waiting[] | select(.key == "acme/widgets#7")] | length')"
check "a settled ticket does not count against the cap" ok \
  "$(sa_stage "$led" "$repo#2" settled; L 7 --area c | jq -r 'if .launch then "ok" else .reason end')"

# --- record: the ledger entry and the baseline reconcile -------------------------------
reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
L 7 --area skills/widgets --out "$out_f" >/dev/null
sa_thread t-7 running 1 0 /wt/seven fix/add-a-frobnicator-to-the-7
sa_pr $repo fix/add-a-frobnicator-to-the-7 none
out=$(bash "$s/launch.sh" record --launch "$out_f" --thread t-7 --ledger "$led"); rc=$?
check_rc "record exits 0" 0 "$rc"
e=$(bash "$s/ledger.sh" --ledger "$led" get "$repo#7")
check "the entry holds the thread, the worktree read from T3 and the branch" '["t-7","/wt/seven","fix/add-a-frobnicator-to-the-7"]' "$(jq -c '[.thread, .worktree, .branch]' <<<"$e")"
check "the fleet's machine key, instance, kind and areas" '["home","claudeAgent","ship",["skills/widgets"]]' "$(jq -c '[.machine, .instance_id, .kind, .areas]' <<<"$e")"
check "the routed tier's model and effort, one spelling" '["opus","high"]' "$(jq -c '[.model, .effort]' <<<"$e")"
check "the baseline reconcile ran: the entry is observed" '{"stage":"running","observed":true}' "$(jq -c '{stage, observed: (.observed != null)}' <<<"$e")"
check "the answer reports the reconcile" '{"checked":1,"errors":[]}' "$(jq -c .reconcile <<<"$out")"
out=$(bash "$s/launch.sh" record --launch "$out_f" --thread t-7 --ledger "$led"); rc=$?
check_rc "a second record of an open ticket exits 1" 1 "$rc"
check "and says it is already in the ledger" "$repo#7 is already in the ledger" "$(jq -r .error <<<"$out")"
check_rc "a launch answer that did not launch is no record, exit 2" 2 "$(echo '{"launch":false}' > "$tmp/no.json"; bash "$s/launch.sh" record --launch "$tmp/no.json" --thread t --ledger "$led" >/dev/null 2>&1; echo $?)"

# --- record never writes `local` for a remote machine ----------------------------------
reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
sa_load 9 12288
L 7 --readings "$readings" --out "$out_f" >/dev/null
check_rc "a remote launch's record without --worktree exits 2" 2 "$(bash "$s/launch.sh" record --launch "$out_f" --thread t-r --ledger "$led" >/dev/null 2>&1; echo $?)"
out=$(bash "$s/launch.sh" record --launch "$out_f" --thread t-r --worktree /wt/remote --ledger "$led" --remote "env-box=$tmp/remote"); rc=$?
check_rc "with --worktree it records" 0 "$rc"
check "the entry names the fleet's key and the environment, never local" '["box","env-box"]' \
  "$(bash "$s/ledger.sh" --ledger "$led" get "$repo#7" | jq -c '[.machine, .environment_id]')"
check "its reconcile read the --remote files, and a missing one is that entry's error" thread-unreadable "$(jq -r '.reconcile.errors[0].kind' <<<"$out")"

# --- a rethread: the stall ladder's rung 3 points the open entry at the new thread ----------
reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
L 7 --out "$out_f" >/dev/null
sa_thread t-7 running 1 0 /wt/seven fix/add-a-frobnicator-to-the-7; sa_pr $repo fix/add-a-frobnicator-to-the-7 none
bash "$s/launch.sh" record --launch "$out_f" --thread t-7 --ledger "$led" >/dev/null
sa_load 9 12288
out=$(L 7 --raise 1 --readings "$readings" --out "$out_f"); rc=$?
check "the open entry does not count against the repo or the cap for its own relaunch" '["env-box","opus"]' "$(jq -c '[.args.environmentId, .args.modelSelection.model]' <<<"$out")"
out=$(bash "$s/launch.sh" record --launch "$out_f" --thread t-8 --worktree /wt/eight --ledger "$led" --rethread --remote "env-box=$tmp/remote"); rc=$?
check_rc "record --rethread exits 0" 0 "$rc"
check "the one entry now holds the new thread, machine, environment and tier, back at launched" '["t-8","box","env-box","opus"]' \
  "$(bash "$s/ledger.sh" --ledger "$led" get "$repo#7" | jq -c '[.thread, .machine, .environment_id, .model]')"
check "and the ledger still has one entry" 1 "$(bash "$s/ledger.sh" --ledger "$led" list | jq '.entries | length')"

# --- end to end: launch, record, reconcile, status --------------------------------------
reset; issue 7 "widgets: add a frobnicator to the pipeline and more" ready-for-agent L bug
out=$(L 7 --out "$out_f")
check "e2e: the launch answers" true "$(jq .launch <<<"$out")"
sa_thread t-7 running 1 0 /wt/seven fix/add-a-frobnicator-to-the-7
sa_pr $repo fix/add-a-frobnicator-to-the-7 none
bash "$s/launch.sh" record --launch "$out_f" --thread t-7 --ledger "$led" >/dev/null
sa_pr $repo fix/add-a-frobnicator-to-the-7 open
sa_thread t-7 idle 1 0 /wt/seven fix/add-a-frobnicator-to-the-7
rec=$(bash "$s/reconcile.sh" --ledger "$led")
check "e2e: the next reconcile finds the entry at rest with its PR open" '{"checked":1,"at_rest":1,"errors":0}' "$(jq -c '{checked, at_rest: (.at_rest | length), errors: (.errors | length)}' <<<"$rec")"
check "e2e: status lists it under Running" 1 "$(bash "$s/status.sh" --ledger "$led" | jq -r .block | grep -c 'Running (1): .*widgets#7')"

finish
