#!/usr/bin/env bash
# super-agent's `quota`, driven through its command line over fake provider CLIs
# on PATH (tests/super-agent-fake.sh): it runs each fleet-file provider's quota
# command and prints one JSON of remaining fractions and resets per bucket, and
# reports a provider whose read fails as unknown instead of failing.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

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

# --- the contract every script keeps -----------------------------------------------
out=$(bash "$s/quota.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: quota" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/quota.sh" --bogus 2>/dev/null); rc=$?
check "a bad flag answers the usage line" "$(sed -n 1p <<<"$(bash "$s/quota.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad flag exits 2" 2 "$rc"
out=$(bash "$s/quota.sh" --fleet "$tmp/none.json" 2>/dev/null); rc=$?
check_rc "a missing fleet file exits 2" 2 "$rc"
check "and names it" "$tmp/none.json: no such file, run setup" "$(jq -r .error <<<"$out")"
printf 'not json\n' > "$tmp/bad.json"
out=$(bash "$s/quota.sh" --fleet "$tmp/bad.json" 2>/dev/null); rc=$?
check_rc "a fleet file that is not JSON exits 2" 2 "$rc"
check "and names it" "$tmp/bad.json: not JSON" "$(jq -r .error <<<"$out")"

# --- each provider's output becomes remaining fractions and resets --------------------
reset
out=$(Q); rc=$?
check_rc "a read exits 0" 0 "$rc"
check "claude: session, weekly all models and a model's weekly bucket, remaining = 1 - used" \
  '[["session","5h",0.96],["week","weekly",0.45],["week-fable","weekly",1]]' \
  "$(jq -c '[.providers.claude.buckets[] | [.id, .window, .remaining]]' <<<"$out")"
check "claude: the reset is the printed text" "Nov 11, 12pm (Africa/Cairo)" \
  "$(jq -r '.providers.claude.buckets[] | select(.id == "week") | .resets' <<<"$out")"
check "codex: the 5 hour and weekly windows, remaining = 1 - used" \
  '[["session","5h",1],["week","weekly",0.46]]' \
  "$(jq -c '[.providers.codex.buckets[] | [.id, .window, .remaining]]' <<<"$out")"
check "codex: the reset epoch is an ISO time" "$(date -u -d @1794383419 +%Y-%m-%dT%H:%M:%SZ)" \
  "$(jq -r '.providers.codex.buckets[] | select(.id == "week") | .resets' <<<"$out")"
check "agy: each group's buckets, with the group named" \
  '[["gemini-weekly","weekly",0.9628,"Gemini Models"],["gemini-5h","5h",1,"Gemini Models"],["3p-weekly","weekly",0.4,"Claude and GPT models"],["3p-5h","5h",1,"Claude and GPT models"]]' \
  "$(jq -c '[.providers.agy.buckets[] | [.id, .window, .remaining, .group]]' <<<"$out")"
check "every provider read is available" 'available available available' \
  "$(jq -r '[.providers.claude, .providers.codex, .providers.agy] | map(.status) | join(" ")' <<<"$out")"
check "each provider's own command ran once, in name order" 'agy claude codex' \
  "$(awk '{print $1}' "$SA_FAKE/calls" | tr '\n' ' ' | sed 's/ $//')"

# --- a provider whose read fails is unknown, and the rest still answer ------------------
reset; sa_provider claude 1 ""
out=$(Q); rc=$?
check_rc "a failing provider does not fail the read" 0 "$rc"
check "it is unknown with the reason" 'unknown quota command exited 1' \
  "$(jq -r '.providers.claude | "\(.status) \(.reason)"' <<<"$out")"
check "and has no buckets" '[]' "$(jq -c .providers.claude.buckets <<<"$out")"
check "the others still answer" 'available available' "$(jq -r '[.providers.codex.status, .providers.agy.status] | join(" ")' <<<"$out")"
reset; sa_provider codex 0 '{"id":1,"result":{}}'
check "output with no rate limits is unknown, not an error" 'unknown quota command printed no quota' \
  "$(Q | jq -r '.providers.codex | "\(.status) \(.reason)"')"
reset; sa_provider agy 0 '{"status":"ERROR","response":""}'
check "an agy answer that is not SUCCESS is unknown" unknown "$(Q | jq -r .providers.agy.status)"
reset; sa_provider claude 0 '{"result":"You are using API billing"}'
check "a claude print with no usage lines is unknown" unknown "$(Q | jq -r .providers.claude.status)"
reset
jq '.providers.agy.quota_command = null' "$fleet" > "$tmp/f2.json"
check "a provider with no quota command is unknown with that reason" 'unknown no quota command in the fleet file' \
  "$(bash "$s/quota.sh" --fleet "$tmp/f2.json" | jq -r '.providers.agy | "\(.status) \(.reason)"')"
reset; SA_FAKE_ABSENT=""; rm -f "$tmp/bin/codex"
check "a provider that is not installed is unknown" unknown "$(Q | jq -r .providers.codex.status)"

finish
