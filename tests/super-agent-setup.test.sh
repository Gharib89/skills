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
mkdir -p "$tmp/bin" "$tmp/fake"
# Hermetic: the real claude, codex and agy sit outside /usr/bin, so a provider
# whose fake is removed is truly not installed.
export PATH="$tmp/bin:/usr/bin:/bin" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
fleet=$tmp/config/fleet.json
S() { bash "$s/setup.sh" --fleet "$fleet" "$@"; }

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

# --- a proposal is printed, and nothing is written without --write --------------
reset
out=$(S --name laptop); rc=$?
check_rc "a proposal exits 0" 0 "$rc"
check "it says it wrote nothing" false "$(jq .written <<<"$out")"
check "and left no file" absent "$([ -e "$fleet" ] && echo present || echo absent)"
f=$(jq -c .fleet <<<"$out")
check "this machine is probed: cores, RAM in GB, GPU" \
  '{"cores":12,"ram_gb":32,"gpu":"NVIDIA GeForce RTX 2070 Super with Max-Q Design","local":true,"probed":true}' \
  "$(jq -c '.machines.laptop | {cores, ram_gb, gpu, local, probed}' <<<"$f")"
check "slots are the lesser of half the cores and RAM over the thread floor" 6 "$(jq '.machines.laptop.slots' <<<"$f")"
check "the load threshold is the core count" 12 "$(jq '.machines.laptop.max_load' <<<"$f")"
check "the per-thread RAM floor is proposed at 4 GB" 4 "$(jq .thread_ram_floor_gb <<<"$f")"
check "linked environments become machines, each with its reachability" \
  '[{"k":"box","id":"env-box","r":true,"p":false},{"k":"down","id":"env-down","r":false,"p":false}]' \
  "$(jq -c '[.machines | to_entries | sort_by(.key)[] | select(.value.local == false) | {k: .key, id: .value.environment_id, r: .value.reachable, p: .value.probed}]' <<<"$f")"
check "an unprobed machine is proposed one slot" 1 "$(jq '.machines.box.slots' <<<"$f")"
check "GitHub accounts, the active one marked" \
  '[{"login":"alice","active":true},{"login":"bob","active":false}]' "$(jq -c .github_accounts <<<"$f")"
check "no repo is active until the owner names one" '[]' "$(jq -c .active_repos <<<"$f")"
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
out=$(S --name laptop); rc=$?
check_rc "a failing provider still exits 0" 0 "$rc"
check "the one that exited nonzero is unavailable, with a reason" \
  '{"status":"unavailable","reason":"quota command exited 1"}' "$(jq -c '.fleet.providers.codex | {status, reason}' <<<"$out")"
check "the one that printed no quota is unavailable too" \
  '{"status":"unavailable","reason":"quota command printed no quota"}' "$(jq -c '.fleet.providers.claude | {status, reason}' <<<"$out")"
check "the others are untouched" available "$(jq -r .fleet.providers.agy.status <<<"$out")"
reset
rm -f "$tmp/bin/codex"
out=$(S --name laptop); rc=$?
check_rc "a provider that is not installed exits 0" 0 "$rc"
check "and is unavailable, saying so" \
  '{"status":"unavailable","reason":"codex is not installed"}' "$(jq -c '.fleet.providers.codex | {status, reason}' <<<"$out")"
sa_fake_install "$tmp/bin"

# --- the other probes failing is not fatal either --------------------------------
reset
rm -f "$SA_FAKE/environments.json" "$SA_FAKE/gh-auth.json"
out=$(S --name laptop); rc=$?
check_rc "no T3 environments and no gh login still exit 0" 0 "$rc"
check "only this machine is listed" laptop "$(jq -r '.fleet.machines | keys | join(",")' <<<"$out")"
check "each failed probe is a warning" 2 "$(jq '.warnings | length' <<<"$out")"
check "no GPU is null" null "$(sa_machine laptop 4 8192; jq .fleet.machines.laptop.gpu <<<"$(S --name laptop)")"

# --- slot proposals follow cores and RAM -----------------------------------------
reset
sa_machine srv 4 8192
check "4 cores and 8 GB: 2 slots" 2 "$(S --name srv | jq .fleet.machines.srv.slots)"
sa_machine srv 16 16384
check "RAM binds before cores: 16 cores and 16 GB, 4 slots" 4 "$(S --name srv | jq .fleet.machines.srv.slots)"
sa_machine srv 2 3072
check "never below one slot" 1 "$(S --name srv | jq .fleet.machines.srv.slots)"

# --- a re-run updates the file and keeps what the owner edited --------------------
reset
S --name laptop --write >/dev/null
jq '.machines.laptop.slots = 2 | .machines.laptop.max_load = 8 | .active_repos = ["Gharib89/skills"]
  | .waivers = [.waivers[0]] | .providers.claude.quota_command = "claude -p /usage" | .note = "mine"' \
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
check "the owner's slot count stays" 2 "$(jq .machines.laptop.slots <<<"$g")"
check "and the load threshold" 8 "$(jq .machines.laptop.max_load <<<"$g")"
check "and the active repos" '["Gharib89/skills"]' "$(jq -c .active_repos <<<"$g")"
check "and a waiver list the owner cut down" 1 "$(jq '.waivers | length' <<<"$g")"
check "and a quota command the owner changed" 'claude -p /usage' "$(jq -r .providers.claude.quota_command <<<"$g")"
check "and a key setup never wrote" mine "$(jq -r .note <<<"$g")"
check "a machine no longer linked is kept, not dropped" present \
  "$(jq -r 'if .machines.down then "present" else "absent" end' <<<"$g")"
check "the re-run keeps the ledger of nothing: a second run changes nothing" "$g" "$(S --name laptop --write >/dev/null; jq -c . "$fleet")"

# --- an unreadable fleet file is refused, not overwritten --------------------------
printf 'not json\n' > "$fleet"
out=$(S --name laptop --write 2>/dev/null); rc=$?
check_rc "a fleet file that is not JSON exits 2" 2 "$rc"
check "and names it" "$fleet: not JSON" "$(jq -r .error <<<"$out")"
check "and is left alone" "not json" "$(cat "$fleet")"

finish
