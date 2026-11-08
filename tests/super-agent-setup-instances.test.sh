#!/usr/bin/env bash
# super-agent's `setup --instances`, driven through its command line over fake
# probes on PATH (tests/super-agent-fake.sh) and a saved `orchestrator_capabilities`
# answer: every enabled T3 provider instance becomes a provider keyed by its
# instance id, with its driver, its own account's quota source, an auth verdict
# (T3's own, else the auth command's) and, for Pi, the agy models; --write saves
# them, a re-run keeps the owner's edits, and the legacy CLI-named keys give way.
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
fleet=$tmp/config/fleet.json
S() { bash "$s/setup.sh" --fleet "$fleet" "$@"; }
P() { S --propose "$@"; }

claude_ok='{"type":"result","result":"Current session: 3% used · resets 14:00"}'
agy_ok='{"conversation_id":"","status":"SUCCESS","response":"Gemini Models\tWeekly Limit Remaining\t96%"}'
codex_ok=$'{"id":1,"result":{"codexHome":"/x"}}\n{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":0}}}}'
reset() {
  rm -f "$fleet" "$SA_FAKE/calls" "$SA_FAKE/environments.json" "$SA_FAKE/gh-auth.json"
  sa_machine laptop 12 32768
  sa_provider claude 0 "$claude_ok"; sa_provider codex 0 "$codex_ok"; sa_provider agy 0 "$agy_ok"
  sa_github alice
}

# --- provider instances: setup proposes each enabled T3 instance, its quota source and auth ------------
# the saved `orchestrator_capabilities` answer: two Claude instances (the default one signed out, the
# second with its own home), Codex, Pi with agy models, and a disabled Cursor
claude_b=$(jq -cn --arg r $'Current session: 2% used · resets x\nCurrent week (all models): 20% used · resets y' '{result:$r}')
inst_reset() {
  reset
  sa_instances "$tmp/inst.json" claudeAgent:claudeAgent:unauth claudeAgent_b:claudeAgent:home=/acct/b pi:pi cursor:cursor:disabled
  sa_account claude b 0 "$claude_b"
}
inst_reset
out=$(P --name laptop --instances "$tmp/inst.json"); rc=$?
check_rc "a proposal over saved instances exits 0" 0 "$rc"
f=$(jq -c .fleet <<<"$out")
check "every enabled instance is a provider keyed by its instance id (a driver no instance covers keeps its CLI key); a disabled one is left out" 'agy claudeAgent claudeAgent_b codex pi' \
  "$(jq -r '.providers | keys | join(" ")' <<<"$f")"
check "the old CLI-named claude key is not proposed beside the instances" null "$(jq -c '.providers.claude' <<<"$f")"
check "each carries its driver" 'claude claude pi' \
  "$(jq -r '[.providers.claudeAgent.driver, .providers.claudeAgent_b.driver, .providers.pi.driver] | join(" ")' <<<"$f")"
check "an instance with a home reads its own account: env set from homePath" '{"CLAUDE_CONFIG_DIR":"/acct/b"}' "$(jq -c .providers.claudeAgent_b.env <<<"$f")"
check "the quota command and a Claude auth command are recorded" 'claude -p "/usage" --output-format json|claude auth status' \
  "$(jq -r '.providers.claudeAgent_b | "\(.quota_command)|\(.auth_command)"' <<<"$f")"
check "T3's own verdict marks the signed-out instance failed, with its reason" 'failed Provider is not authenticated.' \
  "$(jq -r '.providers.claudeAgent | "\(.auth) \(.auth_reason)"' <<<"$f")"
check "an instance whose auth command passes is ok, and its own account's quota was read" 'ok available' \
  "$(jq -r '.providers.claudeAgent_b | "\(.auth) \(.status)"' <<<"$f")"
check "the auth command ran under the instance's account" 1 "$(grep -c '^claude auth status' "$SA_FAKE/calls")"
check "Pi is a provider with its agy quota command, not routed until the owner allows it" 'pi false agy -p /usage --output-format json' \
  "$(jq -r '.providers.pi | "\(.driver) \(.route) \(.quota_command)"' <<<"$f")"
check "its sonnet and opus come from the agy models it lists" '{"sonnet":"antigravity/claude-sonnet-4-6","opus":"antigravity/claude-opus-4-6"}' "$(jq -c .providers.pi.models <<<"$f")"
check "its quota was read through agy" available "$(jq -r .providers.pi.status <<<"$f")"
check "the proposal lists each instance with driver, quota source and auth result" \
  'claudeAgent|claude|the default account|failed claudeAgent_b|claude|CLAUDE_CONFIG_DIR=/acct/b|ok pi|pi|the caller'"'"'s own account|unknown' \
  "$(jq -r '[.instances[] | "\(.instance_id)|\(.driver)|\(.quota_source)|\(.auth)"] | join(" ")' <<<"$out")"
check "a Claude instance with no env beside another one is warned about" 'claudeAgent: no env set' \
  "$(jq -r '.warnings[] | select(startswith("claudeAgent:")) | .[0:23]' <<<"$out")"
check "nothing was written" absent "$([ -e "$fleet" ] && echo present || echo absent)"

# --- each Claude instance reads its own account: ~ expanded, and no env means the default account ------------
# measured 2026-11-08: a literal `~` in CLAUDE_CONFIG_DIR logs the CLI out, and a caller's own value leaks into
# an instance that sets none; Codex keeps the caller's environment
inst_reset
sa_instances "$tmp/inst-home.json" claudeAgent:claudeAgent claudeAgent_b:claudeAgent:home='~/x' codex:codex
sa_claude_auth other 1
rm -f "$SA_FAKE/config-dirs"
out=$(HOME=/h CLAUDE_CONFIG_DIR=/other P --name laptop --instances "$tmp/inst-home.json")
check "a ~ homePath is kept as T3 wrote it in the proposal" '{"CLAUDE_CONFIG_DIR":"~/x"}' "$(jq -c .fleet.providers.claudeAgent_b.env <<<"$out")"
check "each Claude command sees its own config dir: HOME/x, none; Codex keeps the caller's" 'agy|/other claude|/h/x claude|<unset> codex|/other' \
  "$(LC_ALL=C sort -u "$SA_FAKE/config-dirs" | tr '\n' ' ' | sed 's/ $//')"
check "the instance with no env passes its auth command though the caller's account is signed out" 'ok ok' \
  "$(jq -r '.fleet.providers | "\(.claudeAgent.auth) \(.claudeAgent_b.auth)"' <<<"$out")"
check "its quota source says the default account" 'the default account' "$(jq -r '.instances[] | select(.instance_id == "claudeAgent") | .quota_source' <<<"$out")"

# --- a home path from T3's settings file, for a row that carries none (measured: real rows have no homePath) ------
inst_reset
sa_instances "$tmp/inst-nohome.json" claudeAgent_b:claudeAgent
printf '{"providerInstances":{"claudeAgent_b":{"driver":"claudeAgent","enabled":true,"config":{"homePath":"/acct/b"}},"pi":{"driver":"pi"}}}\n' > "$tmp/t3-settings.json"
out=$(P --name laptop --instances "$tmp/inst-nohome.json" --settings "$tmp/t3-settings.json")
check "the settings file's homePath becomes the instance's CLAUDE_CONFIG_DIR, and its account's quota is read" '{"CLAUDE_CONFIG_DIR":"/acct/b"} available' \
  "$(jq -r '.fleet.providers.claudeAgent_b | "\(.env | tostring) \(.status)"' <<<"$out")"
out=$(P --name laptop --instances "$tmp/inst-nohome.json" --settings "$tmp/none.json" 2>/dev/null); rc=$?
check_rc "a settings file that is missing exits 2" 2 "$rc"
# a home path holding a newline is one word of `env`'s arguments, never the program it runs
sa_instances "$tmp/inst-nl.json" claudeAgent_b:claudeAgent
printf '{"providerInstances":{"claudeAgent_b":{"config":{"homePath":"/acct/x\\ntouch"}}}}\n' > "$tmp/t3-nl.json"
sa_account claude touch 0 "$claude_b"
out=$(P --name laptop --instances "$tmp/inst-nl.json" --settings "$tmp/t3-nl.json")
check "a newline in the home path does not replace the command that runs" available "$(jq -r '.fleet.providers.claudeAgent_b.status' <<<"$out")"

# --write saves them, and a re-run keeps the owner's edits and refreshes what was probed
inst_reset
S --write --name laptop --instances "$tmp/inst.json" >/dev/null
check "--write saves the instances" 'claudeAgent claudeAgent_b codex pi' "$(jq -r '[.providers | keys[] | select(. != "agy")] | join(" ")' "$fleet")"
jq '.providers.pi.route = true | .providers.claudeAgent.env = {CLAUDE_CONFIG_DIR: "/acct/a"} | .providers.claudeAgent_b.quota_command = "claude -p /usage --output-format json"' "$fleet" > "$tmp/edit.json" && mv "$tmp/edit.json" "$fleet"
sa_instances "$tmp/inst.json" claudeAgent:claudeAgent claudeAgent_b:claudeAgent:home=/acct/b pi:pi
sa_account claude a 0 "$claude_b"
out=$(S --write --name laptop --instances "$tmp/inst.json")
check "the owner's route allowance on a Pi instance survives" true "$(jq .providers.pi.route "$fleet")"
check "so do an env and a quota command the owner edited" '{"CLAUDE_CONFIG_DIR":"/acct/a"} claude -p /usage --output-format json' \
  "$(jq -r '"\(.providers.claudeAgent.env | tostring) \(.providers.claudeAgent_b.quota_command)"' "$fleet")"
check "an instance T3 now reports signed in is refreshed to ok" 'ok' "$(jq -r .providers.claudeAgent.auth "$fleet")"
check "and its warning is gone with its env set" 0 "$(jq '[.warnings[] | select(startswith("claudeAgent:"))] | length' <<<"$out")"

# an old file keyed by CLI name gives way to the instances that cover its drivers
inst_reset
sa_instances "$tmp/inst.json" claudeAgent:claudeAgent claudeAgent_b:claudeAgent:home=/acct/b codex:codex pi:pi
printf '{"providers":{"claude":{"driver":"claude","quota_command":"claude -p /usage"},"codex":{"driver":"codex","quota_command":"x"}}}\n' > "$fleet"
S --write --name laptop --instances "$tmp/inst.json" >/dev/null
check "the legacy claude key is replaced, so route never launches on an instance T3 lacks" 'agy claudeAgent claudeAgent_b codex pi' "$(jq -r '.providers | keys | join(" ")' "$fleet")"

# the instance list is refused by name when it is not one
inst_reset
printf 'nope\n' > "$tmp/badinst.json"
out=$(P --instances "$tmp/badinst.json" 2>/dev/null); rc=$?
check_rc "an instance file that is not JSON exits 2" 2 "$rc"
check "and names it" "$tmp/badinst.json: not JSON" "$(jq -r .error <<<"$out")"
printf '{"providers":[{"driverKind":"pi"}]}\n' > "$tmp/badinst.json"
out=$(P --instances "$tmp/badinst.json" 2>/dev/null); rc=$?
check_rc "a row with no providerInstanceId exits 2" 2 "$rc"
check "naming the field" "$tmp/badinst.json: every row needs a providerInstanceId and a driverKind" "$(jq -r .error <<<"$out")"
out=$(P --instances "$tmp/none.json" 2>/dev/null); rc=$?
check_rc "a missing instance file exits 2" 2 "$rc"

finish
