# Shared by the super-agent quota tests: fake provider CLIs on a bare PATH, a fleet
# file naming claude, codex and agy, each provider's saved output, `Q` (one quota
# read) and `reset` (every provider back to its saved output). Sourced after
# tests/lib.sh and tests/super-agent-fake.sh.
# shellcheck shell=bash
s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/fake"
for t in bash env jq awk sed grep cat mktemp mv rm mkdir dirname basename tr head tail date timeout sort cut wc chmod diff; do
  ln -s "$(command -v $t)" "$tmp/tools/$t" 2>/dev/null || true
done
export PATH="$tmp/bin:$tmp/tools" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
fleet=$tmp/fleet.json
Q() { bash "$s/quota.sh" --fleet "$fleet"; }

claude_out=$(jq -cn --arg r $'You are currently using your subscription to power your Claude Code usage\n\nCurrent session: 4% used · resets Nov 6, 4:40pm (Africa/Cairo)\nCurrent week (all models): 55% used · resets Nov 11, 12pm (Africa/Cairo)\nCurrent week (Fable): 0% used · resets Nov 11, 12pm (Africa/Cairo)\n\nWhat is contributing to your usage?' '{type:"result", is_error:false, result:$r}')
codex_out=$'{"id":1,"result":{"codexHome":"/x"}}\n{"method":"configWarning","params":{}}\n{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":1793979541},"secondary":{"usedPercent":54,"windowDurationMins":10080,"resetsAt":1794383419},"planType":"plus"}}}'
agy_out='{"status":"SUCCESS","response":"x","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.9628,"reset_time":"2026-11-08T16:51:35Z"},{"id":"gemini-5h","window":"5h","remaining_fraction":1,"reset_time":"2026-11-06T15:37:03Z"}]},{"name":"Claude and GPT models","buckets":[{"id":"3p-weekly","window":"weekly","remaining_fraction":0.4,"reset_time":"2026-11-13T10:38:55Z"},{"id":"3p-5h","window":"5h","remaining_fraction":1,"reset_time":"2026-11-06T15:38:55Z"}]}]}}}'
cat > "$fleet" <<'JSON'
{"providers": {
  "claude": {"driver": "claude", "quota_command": "claude -p \"/usage\" --output-format json"},
  "codex": {"driver": "codex", "quota_command": "codex app-server"},
  "agy": {"driver": "agy", "quota_command": "agy -p /usage --output-format json"}}}
JSON
reset() {
  rm -f "$SA_FAKE/calls"
  sa_provider claude 0 "$claude_out"; sa_provider codex 0 "$codex_out"; sa_provider agy 0 "$agy_out"
}

