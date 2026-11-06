#!/usr/bin/env bash
# super-agent's `place`, driven through its command line over a fleet file, a
# ledger and the fake `t3` (tests/super-agent-fake.sh): this machine first, a GPU
# machine for GPU work, an unreachable or ill-equipped machine skipped, a
# remote launch carrying the machine's environment id, GPU work with no GPU
# machine up recorded as waiting, and no machine ever linked by it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/fake"
for t in bash env jq awk sed grep cat mktemp mv rm mkdir dirname basename tr head tail date timeout sort cut find wc diff chmod; do
  ln -s "$(command -v $t)" "$tmp/tools/$t" || exit 2
done
export PATH="$tmp/bin:$tmp/tools" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
fleet=$tmp/fleet.json led=$tmp/ledger.json readings=$tmp/readings.json
cat > "$fleet" <<'JSON'
{"thread_ram_floor_gb": 4,
 "machines": {
  "home": {"cores": 8, "slots": 3, "reserve": 1, "max_load": 8, "gpu": null, "gh_logins": ["alice", "bob"]},
  "gpubox": {"environment_id": "env-gpu", "cores": 16, "slots": 4, "max_load": 16, "gpu": "RTX 4090", "gh_logins": ["alice"]},
  "plain": {"environment_id": "env-plain", "cores": 4, "slots": 2, "max_load": 4, "gpu": null, "gh_logins": ["alice", "bob"]},
  "zghost": {"slots": 2, "max_load": 4, "gpu": null}}}
JSON
envs='[{"environmentId":"env-gpu","label":"gpubox","status":"reachable"},{"environmentId":"env-plain","label":"plain","status":"reachable"}]'
P() { bash "$s/place.sh" --fleet "$fleet" --ledger "$led" --own home --repo Gharib89/skills "$@"; }
reset() {
  rm -f "$led" "$SA_FAKE/calls"; sa_machine home 8 16384; sa_load 0.5 12288
  sa_environments "$envs"
  printf '{"gpubox":{"load1":1,"free_gb":20},"plain":{"load1":0.5,"free_gb":6}}\n' > "$readings"
}

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/place.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: place" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/place.sh" --bogus 2>/dev/null); rc=$?
check "a bad flag answers the usage line" "$(sed -n 1p <<<"$(bash "$s/place.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad flag exits 2" 2 "$rc"

# --- this machine first ----------------------------------------------------------
reset
out=$(P --readings "$readings"); rc=$?
check_rc "a placement exits 0" 0 "$rc"
check "this machine is picked when it fits, with no environment id" \
  '{"machine":"home","environment_id":null,"local":true}' "$(jq -c .placed <<<"$out")"
check "and no other machine was looked at" '[]' "$(jq -c .considered <<<"$out")"
check "nothing waits" false "$(jq .waiting <<<"$out")"

# --- a full own machine hands over to the next that fits, by its environment id ------
sa_load 9 12288
out=$(P --readings "$readings")
check "an own machine over its load limit is passed over" \
  '{"machine":"home","outcome":"refused:load"}' "$(jq -c '.considered[0]' <<<"$out")"
check "the next linked machine takes the launch, and its environment id is what the launch passes" \
  '{"machine":"gpubox","environment_id":"env-gpu","local":false}' "$(jq -c .placed <<<"$out")"
sa_load 0.5 2048
check "an own machine short of free RAM is passed over too" gpubox "$(P --readings "$readings" | jq -r .placed.machine)"

# --- a remote machine with no live reading is asked for, never guessed -----------------
sa_load 9 12288
out=$(P)
check "no reading for the next candidate is a request for one" '{"machine":"gpubox","environment_id":"env-gpu"}' "$(jq -c .need_reading <<<"$out")"
check "which is no placement and no wait" '[null,false]' "$(jq -c '[.placed, .waiting]' <<<"$out")"
check "and writes nothing" absent "$([ -e "$led" ] && echo present || echo absent)"

# --- GPU work goes to the machine with the GPU ---------------------------------------
reset
out=$(P --gpu --readings "$readings")
check "GPU work skips this machine though it fits" \
  '{"machine":"gpubox","environment_id":"env-gpu","local":false}' "$(jq -c .placed <<<"$out")"
check "naming why" '{"machine":"home","outcome":"skipped:no-gpu"}' "$(jq -c '.considered[0]' <<<"$out")"

# --- an unreachable machine is skipped for the next that fits ---------------------------
sa_environments '[{"environmentId":"env-gpu","label":"gpubox","status":"unreachable"},{"environmentId":"env-plain","label":"plain","status":"reachable"}]'
sa_load 9 12288
out=$(P --readings "$readings")
check "the machine that is down is skipped" '{"machine":"gpubox","outcome":"skipped:unreachable"}' "$(jq -c '.considered[1]' <<<"$out")"
check "and the next one that fits takes it" plain "$(jq -r .placed.machine <<<"$out")"
rm -f "$SA_FAKE/environments.json"
out=$(P --readings "$readings" --number 9 2>/dev/null); rc=$?
check_rc "an environment list that fails is a tooling fault, exit 2" 2 "$rc"
check "and records no waiting row, since reachability is unknown, not down" 0 \
  "$(jq '(.waiting // []) | length' "$led" 2>/dev/null || echo 0)"

# --- GPU work with no GPU machine up waits in the ledger -------------------------------
reset
sa_environments '[{"environmentId":"env-gpu","label":"gpubox","status":"unreachable"},{"environmentId":"env-plain","label":"plain","status":"reachable"}]'
out=$(P --gpu --readings "$readings" --number 42)
check "GPU work with its machine down is placed nowhere" '[null,true]' "$(jq -c '[.placed, .waiting]' <<<"$out")"
check "and the reason says it was the GPU" gpu "$(jq -r '.reason | split(":")[0]' <<<"$out")"
check "the ledger records it as waiting" \
  '{"key":"Gharib89/skills#42","reason":"gpu: no reachable machine with a GPU"}' \
  "$(jq -c '.waiting[0] | {key, reason}' "$led")"
check "no entry, thread or slot is taken" '{}' "$(jq -c .entries "$led")"
sa_environments "$envs"
out=$(P --gpu --readings "$readings" --number 42)
check "once the GPU machine is up the same ticket is placed" gpubox "$(jq -r .placed.machine <<<"$out")"
check "and its waiting row is gone" '[]' "$(jq -c .waiting "$led")"

# --- the account the repo needs ----------------------------------------------------------
reset
sa_load 9 12288
out=$(P --account bob --readings "$readings")
check "a machine without the repo's gh login is skipped" '{"machine":"gpubox","outcome":"skipped:account"}' "$(jq -c '.considered[1]' <<<"$out")"
check "the next one holding the login takes it" plain "$(jq -r .placed.machine <<<"$out")"

# --- a machine the caller excludes -------------------------------------------------------
out=$(P --exclude gpubox --readings "$readings")
check "an excluded machine is skipped" '{"machine":"gpubox","outcome":"skipped:excluded"}' "$(jq -c '.considered[1]' <<<"$out")"
check "and the launch goes on" plain "$(jq -r .placed.machine <<<"$out")"

# --- nothing fits: waiting, with each reason ------------------------------------------------
reset
sa_load 9 12288
printf '{"gpubox":{"load1":99,"free_gb":20},"plain":{"load1":0.5,"free_gb":1}}\n' > "$readings"
out=$(P --readings "$readings" --number 7)
check "no machine fits: waiting, nothing placed" '[null,true]' "$(jq -c '[.placed, .waiting]' <<<"$out")"
check "each refusal is named" 'refused:load refused:load refused:ram' "$(jq -r '[.considered[].outcome | select(startswith("refused"))] | join(" ")' <<<"$out")"
check "a machine the fleet holds with no environment id cannot be launched on" \
  '{"machine":"zghost","outcome":"skipped:no-environment"}' "$(jq -c '.considered[] | select(.machine == "zghost")' <<<"$out")"
check "and the ledger holds it as waiting" 'Gharib89/skills#7' "$(jq -r '.waiting[0].key' "$led")"

# --- the same repo beside itself -------------------------------------------------------------
reset
bash "$s/ledger.sh" --ledger "$led" add --repo Gharib89/skills --number 1 --thread t-1 --worktree /wt/1 --branch b-1 --machine home --area skills/ship >/dev/null
check "a same-repo ticket with an overlapping area waits, whichever machine" true "$(P --area skills/ship/scripts --readings "$readings" | jq .waiting)"
check "with the ticket in the way named" 1 "$(P --area skills/ship --readings "$readings" | jq '.reason | test("skills#1") | if . then 1 else 0 end')"
check "an apart area is placed beside it" home "$(P --area skills/drive-session --readings "$readings" | jq -r .placed.machine)"

# --- a rethread of a ticket the ledger already holds ---------------------------------------
reset
bash "$s/ledger.sh" --ledger "$led" add --repo Gharib89/skills --number 1 --thread t-1 --worktree /wt/1 --branch b-1 --machine home --area skills/ship >/dev/null
out=$(P --area skills/ship --readings "$readings" --number 1); rc=$?
check_rc "a rethread does not conflict with its own open entry" 0 "$rc"
check "and is placed, its own slot not counted" home "$(jq -r .placed.machine <<<"$out")"

# --- a machine the fleet file lacks as this one is not a candidate -----------------------
reset
out=$(bash "$s/place.sh" --fleet "$fleet" --ledger "$led" --own elsewhere --repo Gharib89/skills --readings "$readings")
check "an own key the fleet file does not hold is skipped, not refused" gpubox "$(jq -r .placed.machine <<<"$out")"

# --- no machine is ever linked ---------------------------------------------------------------
check "no call of any run above was a link, unlink or launch" 0 "$(grep -c '^t3 environment \(link\|unlink\)\|^t3 thread start' "$SA_FAKE/calls")"
check "the fleet file the runs read holds no host, user or key" 0 \
  "$(jq '[.. | strings | select(test("@|ssh|\\.pem|id_rsa"))] | length' "$fleet")"

finish
