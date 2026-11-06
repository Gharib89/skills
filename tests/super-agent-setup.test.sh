#!/usr/bin/env bash
# super-agent's `setup`, driven through its command line over fake probes on
# PATH (tests/super-agent-fake.sh): it proposes a fleet file from what the
# machine, the linked T3 environments, GitHub and each provider answer, writes
# it only when told to, records a provider whose quota command fails as
# unavailable, and keeps what the owner edited on a re-run.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/fake"
# Hermetic: only the tools the script itself needs are linked in, so the real
# nvidia-smi, claude, codex and agy cannot answer for a fake that is removed.
for t in bash env jq awk sed grep cat mktemp mv rm mkdir dirname basename tr head tail date timeout sort cut find wc diff chmod; do
  ln -s "$(command -v $t)" "$tmp/tools/$t" || exit 2
done
export PATH="$tmp/bin:$tmp/tools" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
fleet=$tmp/config/fleet.json
S() { bash "$s/setup.sh" --fleet "$fleet" "$@"; }
P() { S --propose "$@"; }

claude_ok='{"type":"result","result":"Current session: 3% used · resets 14:00"}'
agy_ok='{"conversation_id":"","status":"SUCCESS","response":"Gemini Models\tWeekly Limit Remaining\t96%"}'
codex_ok=$'{"id":1,"result":{"codexHome":"/x"}}\n{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":0}}}}'
envs='[{"environmentId":"env-box","label":"box","status":"reachable"},{"environmentId":"env-down","label":"down","status":"unreachable"}]'
reset() {
  rm -f "$fleet" "$SA_FAKE/calls" "$SA_FAKE/environments.json" "$SA_FAKE/gh-auth.json"
  sa_machine laptop 12 32768 "NVIDIA GeForce RTX 2070 Super with Max-Q Design"
  sa_provider claude 0 "$claude_ok"; sa_provider codex 0 "$codex_ok"; sa_provider agy 0 "$agy_ok"
  sa_environments "$envs"; sa_github alice bob
}

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/setup.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: setup" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/setup.sh" --bogus 2>/dev/null); rc=$?
check "a bad flag answers the usage line" "$(sed -n 1p <<<"$(bash "$s/setup.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad flag exits 2" 2 "$rc"
out=$(bash "$s/setup.sh" 2>/dev/null); rc=$?
check_rc "a bare call, which names neither --propose nor --write, exits 2" 2 "$rc"
check "and writes nothing" absent "$([ -e "$fleet" ] && echo present || echo absent)"

# --- a proposal is printed, and nothing is written without --write --------------
reset
out=$(P --name laptop); rc=$?
check_rc "a proposal exits 0" 0 "$rc"
check "it says it wrote nothing" false "$(jq .written <<<"$out")"
check "and left no file" absent "$([ -e "$fleet" ] && echo present || echo absent)"
f=$(jq -c .fleet <<<"$out")
check "this machine is probed: cores, RAM in GB, GPU" \
  '{"cores":12,"ram_gb":32,"gpu":"NVIDIA GeForce RTX 2070 Super with Max-Q Design","probed":true}' \
  "$(jq -c '.machines.laptop | {cores, ram_gb, gpu, probed}' <<<"$f")"
check "slots are the lesser of half the cores and RAM over the thread floor" 6 "$(jq '.machines.laptop.slots' <<<"$f")"
check "the load threshold is the core count" 12 "$(jq '.machines.laptop.max_load' <<<"$f")"
check "the per-thread RAM floor is proposed at 4 GB" 4 "$(jq .thread_ram_floor_gb <<<"$f")"
check "linked environments become machines, each with its reachability" \
  '[{"k":"box","id":"env-box","r":true,"p":false},{"k":"down","id":"env-down","r":false,"p":false}]' \
  "$(jq -c '[.machines | to_entries | sort_by(.key)[] | select(.value.environment_id != null) | {k: .key, id: .value.environment_id, r: .value.reachable, p: .value.probed}]' <<<"$f")"
check "an unprobed machine is proposed one slot" 1 "$(jq '.machines.box.slots' <<<"$f")"
check "GitHub accounts, the active one marked" \
  '[{"login":"alice","active":true},{"login":"bob","active":false}]' "$(jq -c .github_accounts <<<"$f")"
check "no repo is active until the owner names one" '[]' "$(jq -c .active_repos <<<"$f")"
check "the work week is proposed Monday to Friday, for the owner to edit" '[1,2,3,4,5]' "$(jq -c .work_week <<<"$f")"
check "the three default standing waivers, each with its condition" \
  'codex-usage-limit offline-live-e2e last-fix-after-cap' "$(jq -r '[.waivers[].id] | join(" ")' <<<"$f")"
check "every waiver states its condition" 3 "$(jq '[.waivers[] | select(.condition | length > 20)] | length' <<<"$f")"
check "each provider is available with its quota command recorded" \
  'available available available' \
  "$(jq -r '[.providers.claude, .providers.codex, .providers.agy] | map(.status) | join(" ")' <<<"$f")"
check "claude's quota command is the measured /usage print" \
  'claude -p "/usage" --output-format json' "$(jq -r .providers.claude.quota_command <<<"$f")"
check "agy's quota command is the measured /usage print" \
  'agy -p /usage --output-format json' "$(jq -r .providers.agy.quota_command <<<"$f")"
check "codex's quota command asks the app server for the rate limits" 1 \
  "$(jq -r '.providers.codex.quota_command | test("account/rateLimits/read") and test("codex app-server") | if . then 1 else 0 end' <<<"$f")"
check "and holds its stdin open while the server answers, which exits at once on end of input (measured with codex 0.166.0)" 1 \
  "$(jq -r '.providers.codex.quota_command | test("sleep [0-9]+; *}? *\\| *timeout") | if . then 1 else 0 end' <<<"$f")"

# --- --write puts the same file on disk, atomically, in a directory it creates ---
out=$(S --name laptop --write); rc=$?
check_rc "--write exits 0" 0 "$rc"
check "it says it wrote" true "$(jq .written <<<"$out")"
check "the file is the proposal" "$f" "$(jq -c . "$fleet")"
check "no temp file is left beside it" 1 "$(find "$(dirname "$fleet")" -type f | wc -l)"

# --- a failing quota command is recorded, never fatal ---------------------------
reset
sa_provider codex 1 "boom"
sa_provider claude 0 "not json at all"
out=$(P --name laptop); rc=$?
check_rc "a failing provider still exits 0" 0 "$rc"
check "the one that exited nonzero is unavailable, with a reason" \
  '{"status":"unavailable","reason":"quota command exited 1"}' "$(jq -c '.fleet.providers.codex | {status, reason}' <<<"$out")"
check "the one that printed no quota is unavailable too" \
  '{"status":"unavailable","reason":"quota command printed no quota"}' "$(jq -c '.fleet.providers.claude | {status, reason}' <<<"$out")"
check "the others are untouched" available "$(jq -r .fleet.providers.agy.status <<<"$out")"
reset
rm -f "$tmp/bin/codex"
out=$(P --name laptop); rc=$?
check_rc "a provider that is not installed exits 0" 0 "$rc"
check "and is unavailable, saying so" \
  '{"status":"unavailable","reason":"codex is not installed"}' "$(jq -c '.fleet.providers.codex | {status, reason}' <<<"$out")"
sa_fake_install "$tmp/bin"

# --- the other probes failing is not fatal either --------------------------------
reset
rm -f "$SA_FAKE/environments.json" "$SA_FAKE/gh-auth.json"
out=$(P --name laptop); rc=$?
check_rc "no T3 environments and no gh login still exit 0" 0 "$rc"
check "only this machine is listed" laptop "$(jq -r '.fleet.machines | keys | join(",")' <<<"$out")"
check "each failed probe is a warning" 2 "$(jq '.warnings | length' <<<"$out")"
check "no GPU is null" null "$(sa_machine laptop 4 8192; jq .fleet.machines.laptop.gpu <<<"$(P --name laptop)")"

# --- slot proposals follow cores and RAM -----------------------------------------
reset
sa_machine srv 4 8192
check "4 cores and 8 GB: 2 slots" 2 "$(P --name srv | jq .fleet.machines.srv.slots)"
sa_machine srv 16 16384
check "RAM binds before cores: 16 cores and 16 GB, 4 slots" 4 "$(P --name srv | jq .fleet.machines.srv.slots)"
sa_machine srv 2 3072
check "never below one slot" 1 "$(P --name srv | jq .fleet.machines.srv.slots)"

# --- a re-run updates the file and keeps what the owner edited --------------------
reset
S --name laptop --write >/dev/null
jq '.machines.laptop.slots = 2 | .machines.laptop.max_load = 8 | .active_repos = ["Gharib89/skills"]
  | .waivers = [.waivers[0]] | .work_week = [0,1,2,3,4] | .providers.claude.quota_command = "claude -p /usage" | .note = "mine"' \
  "$fleet" > "$tmp/edited.json" && mv "$tmp/edited.json" "$fleet"
sa_machine laptop 16 65536 "A GPU"
sa_provider agy 1 "down now"
sa_github alice
out=$(S --name laptop --write); rc=$?
check_rc "the re-run exits 0" 0 "$rc"
g=$(jq -c . "$fleet")
check "probed facts are refreshed: cores, RAM, GPU" '{"cores":16,"ram_gb":64,"gpu":"A GPU"}' \
  "$(jq -c '.machines.laptop | {cores, ram_gb, gpu}' <<<"$g")"
check "so is a provider's status" unavailable "$(jq -r .providers.agy.status <<<"$g")"
check "and the account list" '[{"login":"alice","active":true}]' "$(jq -c .github_accounts <<<"$g")"
check "the re-run probed the command the owner edited, not the default" \
  "claude -p /usage" "$(grep '^claude ' "$SA_FAKE/calls" | tail -1)"
check "the owner's slot count stays" 2 "$(jq .machines.laptop.slots <<<"$g")"
check "and the load threshold" 8 "$(jq .machines.laptop.max_load <<<"$g")"
check "and the active repos" '["Gharib89/skills"]' "$(jq -c .active_repos <<<"$g")"
check "and a waiver list the owner cut down" 1 "$(jq '.waivers | length' <<<"$g")"
check "and the work week the owner set" '[0,1,2,3,4]' "$(jq -c .work_week <<<"$g")"
check "and a quota command the owner changed" 'claude -p /usage' "$(jq -r .providers.claude.quota_command <<<"$g")"
check "and a key setup never wrote" mine "$(jq -r .note <<<"$g")"
check "a machine no longer linked is kept, not dropped" present \
  "$(jq -r 'if .machines.down then "present" else "absent" end' <<<"$g")"
check "a second run changes nothing" "$g" "$(S --name laptop --write >/dev/null; jq -c . "$fleet")"

# --- a failed GPU read is not a verdict --------------------------------------------
reset
S --name laptop --write >/dev/null
sa_machine laptop 12 32768
sa_gpu_failing
out=$(P --name laptop); rc=$?
check_rc "an nvidia-smi that fails still exits 0" 0 "$rc"
check "the GPU the file already holds is kept" "NVIDIA GeForce RTX 2070 Super with Max-Q Design" "$(jq -r .fleet.machines.laptop.gpu <<<"$out")"
check "and the failure is a warning" "nvidia-smi failed: gpu left as the file has it" "$(jq -r '.warnings[0]' <<<"$out")"
sa_machine laptop 12 32768
check "a machine without the tool is no GPU, even where the file held one" null "$(P --name laptop | jq .fleet.machines.laptop.gpu)"

# --- a file shared between machines keeps what another machine's run measured ------
reset
cat > "$fleet" <<'JSON'
{"machines": {"box": {"environment_id": "env-box", "probed": true, "cores": 4, "ram_gb": 8, "slots": 2, "max_load": 4}}}
JSON
out=$(S --name laptop --write); rc=$?
check_rc "a run on another machine exits 0" 0 "$rc"
check "the machine another run sized stays probed, with its cores and slots" \
  '{"probed":true,"cores":4,"slots":2}' "$(jq -c '.fleet.machines.box | {probed, cores, slots}' <<<"$out")"
check "its reachability is refreshed" true "$(jq .fleet.machines.box.reachable <<<"$out")"
check "only one machine is this one's own, the file holds no local flag" 0 \
  "$(jq '[.fleet.machines[] | select(has("local"))] | length' <<<"$out")"

# --- an unreadable fleet file is refused, not overwritten --------------------------
printf 'not json\n' > "$fleet"
out=$(S --name laptop --write 2>/dev/null); rc=$?
check_rc "a fleet file that is not JSON exits 2" 2 "$rc"
check "and names it" "$fleet: not JSON" "$(jq -r .error <<<"$out")"
check "and is left alone" "not json" "$(cat "$fleet")"

for bad in '[]' '{"providers":[]}' '{"machines":"x"}' '{"waivers":{}}' '{"active_repos":"x"}' '{"work_week":[7]}' '{"work_week":[1,1]}' '{"work_week":"x"}' '{"providers":{"claude":{"quota_command":3}}}'; do
  printf '%s\n' "$bad" > "$fleet"
  out=$(S --name laptop --write 2>/dev/null); rc=$?
  check_rc "a fleet file shaped $bad exits 2" 2 "$rc"
  check "and is left alone: $bad" "$bad" "$(cat "$fleet")"
done
printf '{"providers":[]}\n' > "$fleet"
check "the refusal names the file and the field" "$fleet: providers must be an object" \
  "$(S --name laptop --write 2>/dev/null | jq -r .error)"

# --- this machine's capabilities, from the same probe a linked machine runs -------------
reset
f=$(P --name laptop | jq -c .fleet)
check "this machine's gh logins and provider CLIs are recorded" \
  '{"gh_logins":["alice","bob"],"clis":{"claude":true,"codex":true,"agy":true,"gh":true,"bun":false}}' \
  "$(jq -c '.machines.laptop | {gh_logins, clis}' <<<"$f")"
check "one slot is kept for the owner's messages on this machine" 1 "$(jq .machines.laptop.reserve <<<"$f")"
check "and none on a linked one" null "$(jq .machines.box.reserve <<<"$f")"

# --- a linked machine is probed through a scratch thread the caller runs ------------------
probe_line() { # <cores> <ram_gb> <gpu json> <logins json>
  printf 'Probe thread reply:\n{"cores":%s,"ram_gb":%s,"free_gb":6.1,"load1":0.3,"gpu":%s,"gpu_failed":false,"clis":{"claude":true,"codex":false,"agy":false,"gh":true,"bun":false},"gh_logins":%s}\n' "$1" "$2" "$3" "$4"
}
probe_line 4 8 null '["alice"]' > "$tmp/box.reply"
reset
out=$(P --name laptop)
check "the first call lists each reachable linked machine to probe, and never an unreachable one" \
  '[{"machine":"box","environment_id":"env-box"}]' "$(jq -c .to_probe <<<"$out")"
out=$(P --name laptop --probe env-box="$tmp/box.reply"); rc=$?
check_rc "a call with the reply exits 0" 0 "$rc"
check "nothing is left to probe" '[]' "$(jq -c .to_probe <<<"$out")"
check "the reply's facts are merged under the machine" \
  '{"probed":true,"cores":4,"ram_gb":8,"gpu":null,"gh_logins":["alice"],"environment_id":"env-box","reachable":true}' \
  "$(jq -c '.fleet.machines.box | {probed, cores, ram_gb, gpu, gh_logins, environment_id, reachable}' <<<"$out")"
check "with its provider CLIs" '{"claude":true,"codex":false,"agy":false,"gh":true,"bun":false}' "$(jq -c .fleet.machines.box.clis <<<"$out")"
check "never probed, its slots and load threshold are the computed ones, not the placeholder" '{"slots":2,"max_load":4}' \
  "$(jq -c '.fleet.machines.box | {slots, max_load}' <<<"$out")"
check "a live reading is not a fact the file keeps" '[]' "$(jq -c '[.fleet.machines.box | keys[] | select(. == "load1" or . == "free_gb")]' <<<"$out")"
check "a linked machine's quota is the account's, so the file keeps none under it" '[]' \
  "$(jq -c '[.fleet.machines.box | keys[] | select(test("quota|providers"))]' <<<"$out")"
check "the file holds the environment id and no host, user or key" \
  '["clis","cores","environment_id","gh_logins","gpu","max_load","probed","proposed_slots","ram_gb","reachable","slots"]' \
  "$(jq -c '.fleet.machines.box | keys' <<<"$out")"
check "a GPU the probe found is recorded" "RTX 4090" \
  "$(probe_line 4 8 '"RTX 4090"' '[]' > "$tmp/gpu.reply"; P --name laptop --probe env-box="$tmp/gpu.reply" | jq -r .fleet.machines.box.gpu)"

# --- a re-run keeps the owner's slot edits and moves only the probed facts ----------------
reset
S --name laptop --probe env-box="$tmp/box.reply" --write >/dev/null
jq '.machines.box.slots = 3 | .machines.box.max_load = 2' "$fleet" > "$tmp/e.json" && mv "$tmp/e.json" "$fleet"
probe_line 8 32 null '["alice","bob"]' > "$tmp/box2.reply"
out=$(S --name laptop --probe env-box="$tmp/box2.reply" --write); g=$(jq -c .fleet <<<"$out")
check "the facts are refreshed" '{"cores":8,"ram_gb":32,"gh_logins":["alice","bob"]}' "$(jq -c '.machines.box | {cores, ram_gb, gh_logins}' <<<"$g")"
check "the owner's slots and load threshold stay" '{"slots":3,"max_load":2}' "$(jq -c '.machines.box | {slots, max_load}' <<<"$g")"
check "the proposal moves, so the owner can see what a re-measure would set" 4 "$(jq .machines.box.proposed_slots <<<"$g")"
check "a second identical run changes nothing" "$g" "$(S --name laptop --probe env-box="$tmp/box2.reply" --write >/dev/null; jq -c . "$fleet")"

# --- an unreachable machine keeps its previous facts and is probed once it is back ---------
sa_environments '[{"environmentId":"env-box","label":"box","status":"unreachable"}]'
out=$(S --name laptop --probe env-box="$tmp/box.reply" --write)
check "an unreachable machine is recorded unreachable" false "$(jq .fleet.machines.box.reachable <<<"$out")"
check "with its previous facts kept, a reply for it unmerged" '{"cores":8,"ram_gb":32}' "$(jq -c '.fleet.machines.box | {cores, ram_gb}' <<<"$out")"
check "and the reply's refusal is a warning" 1 "$(jq '[.warnings[] | select(startswith("box: unreachable"))] | length' <<<"$out")"
check "it is not offered for probing while down" '[]' "$(jq -c .to_probe <<<"$out")"
sa_environments "$envs"
check "the next run that finds it reachable offers it again" '[{"machine":"box","environment_id":"env-box"}]' "$(P --name laptop | jq -c .to_probe)"

# --- a reply that is no probe is a warning, never a merge ---------------------------------
reset
printf 'I could not run it\n' > "$tmp/bad.reply"
out=$(P --name laptop --probe env-box="$tmp/bad.reply"); rc=$?
check_rc "a reply with no probe line exits 0" 0 "$rc"
check "and is a warning naming the machine" 1 "$(jq '[.warnings[] | select(startswith("box: no probe line"))] | length' <<<"$out")"
check "its facts stay the unprobed ones" false "$(jq .fleet.machines.box.probed <<<"$out")"
printf '{"error":"jq not installed"}\n' > "$tmp/err.reply"
check "a probe's own error is carried into the warning" "box: no probe line in $tmp/err.reply: jq not installed" \
  "$(P --name laptop --probe env-box="$tmp/err.reply" | jq -r '.warnings[0]')"
check "a malformed --probe is a usage error" 2 "$(P --name laptop --probe nofile >/dev/null 2>&1; echo $?)"
check "setup never links a machine" 0 "$(grep -c '^t3 environment link' "$SA_FAKE/calls")"

finish
