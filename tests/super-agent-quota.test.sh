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
mkdir -p "$tmp/cfg/super-agent"; printf '{"providers":{}}\n' > "$tmp/cfg/super-agent/fleet.json"
out=$(XDG_CONFIG_HOME="$tmp/cfg" HOME="$tmp/cfg" bash "$s/quota.sh" 2>/dev/null); rc=$?
check_rc "a bare call exits 2 even where the owner keeps a fleet file" 2 "$rc"
check "and answers the usage line" "$(sed -n 1p <<<"$(bash "$s/quota.sh" --help)")" "$(jq -r .error <<<"$out")"
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
reset; rm -f "$tmp/bin/codex"
check "a provider that is not installed is unknown" unknown "$(Q | jq -r .providers.codex.status)"

reset; sa_provider agy 0 '{"status":"SUCCESS","command":{"data":{"groups":[{"name":"G","buckets":[{"id":"a","window":"weekly","reset_time":"x"},{"id":"b","window":"5h","remaining_fraction":0.5,"reset_time":"y"}]}]}}}'
check "an agy bucket with no remaining fraction is dropped" '["b"]' "$(Q | jq -c '[.providers.agy.buckets[].id]')"

# a provider key is read as a name, never globbed against the working directory
jq -n '{providers: {"*": {}}}' > "$tmp/glob.json"
check "a provider keyed * is one provider, not every file here" '["*"]' "$(bash "$s/quota.sh" --fleet "$tmp/glob.json" | jq -c '.providers | keys')"

# --- a provider is a T3 instance: its own account, its own auth probe ----------------------------
# two Claude instances, each its own CLAUDE_CONFIG_DIR, and a Pi instance that reads agy's buckets
claude_a=$(jq -cn --arg r $'Current session: 1% used · resets x\nCurrent week (all models): 99% used · resets y' '{result:$r}')
claude_b=$(jq -cn --arg r $'Current session: 2% used · resets x\nCurrent week (all models): 20% used · resets y' '{result:$r}')
cat > "$tmp/inst.json" <<'JSON'
{"providers": {
  "claudeAgent": {"driver": "claude", "env": {"CLAUDE_CONFIG_DIR": "/acct/a"}, "quota_command": "claude -p \"/usage\" --output-format json", "auth_command": "claude auth status"},
  "claudeAgent_b": {"driver": "claude", "env": {"CLAUDE_CONFIG_DIR": "/acct/b"}, "quota_command": "claude -p \"/usage\" --output-format json", "auth_command": "claude auth status"},
  "pi": {"driver": "pi", "route": true, "quota_command": "agy -p /usage --output-format json"}}}
JSON
reset; sa_account claude a 0 "$claude_a"; sa_account claude b 0 "$claude_b"
out=$(bash "$s/quota.sh" --fleet "$tmp/inst.json"); rc=$?
check_rc "an instance-keyed fleet file reads" 0 "$rc"
check "two Claude instances give two separate readings, each under its own instance" '0.01 0.8' \
  "$(jq -r '[.providers.claudeAgent, .providers.claudeAgent_b | .buckets[] | select(.id == "week") | .remaining] | join(" ")' <<<"$out")"
check "each entry names its instance and driver" 'claudeAgent claude claudeAgent_b claude pi pi' \
  "$(jq -r '[.providers | to_entries[] | .key, .value.driver] | join(" ")' <<<"$out")"
check "a Pi instance reads its buckets through the agy parser, groups kept" '["Claude and GPT models","Gemini Models"]' \
  "$(jq -c '[.providers.pi.buckets[].group] | unique' <<<"$out")"
check "auth is ok where the auth command exits 0" 'ok ok' "$(jq -r '[.providers.claudeAgent.auth, .providers.claudeAgent_b.auth] | join(" ")' <<<"$out")"
check "auth is unknown for an instance with no auth command, with the reason" 'unknown no auth command in the fleet file' \
  "$(jq -r '.providers.pi | "\(.auth) \(.auth_reason)"' <<<"$out")"
check "each Claude instance's auth probe ran once" 2 "$(grep -c '^claude auth status' "$SA_FAKE/calls")"

# the auth command fails: failed, with the reason, and the quota is still read
reset; sa_account claude a 0 "$claude_a"; sa_account claude b 0 "$claude_b"; sa_claude_auth a 1
out=$(bash "$s/quota.sh" --fleet "$tmp/inst.json")
check "a failing auth command is auth failed with its exit" 'failed auth command exited 1' \
  "$(jq -r '.providers.claudeAgent | "\(.auth) \(.auth_reason)"' <<<"$out")"
check "the other instance is untouched" ok "$(jq -r .providers.claudeAgent_b.auth <<<"$out")"
check "the failed instance's quota is still read" available "$(jq -r .providers.claudeAgent.status <<<"$out")"

# the verdict setup recorded from T3 holds where no command can tell the account apart, for 24 h
reset; sa_account claude b 0 "$claude_b"
# On a pinned clock (SA_NOW, an epoch), so the window reads the same at every hour.
pin=1800000000
ts() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
now=$(ts $pin) old=$(ts $((pin - 172800)))
rec() { # <file> <source|-> <checked|-> : record failed on claudeAgent_b
  jq --arg s "$2" --arg c "$3" '.providers.claudeAgent_b.auth = "failed" | .providers.claudeAgent_b.auth_reason = "Provider is not authenticated."
    | if $s != "-" then .providers.claudeAgent_b.auth_source = $s else . end | if $c != "-" then .providers.claudeAgent_b.auth_checked = $c else . end' "$tmp/inst.json" > "$1"
}
authof() { jq -r '.providers.claudeAgent_b | "\(.auth) \(.auth_reason // "")"' <<<"$1"; }
rec "$tmp/inst2.json" t3 "$now"
check "a T3-sourced failure inside the window stands though the live command passes" 'failed Provider is not authenticated.' \
  "$(authof "$(SA_NOW=$pin bash "$s/quota.sh" --fleet "$tmp/inst2.json")")"
rec "$tmp/inst2.json" t3 "$old"
check "the same T3-sourced failure past the window no longer reads failed" 'ok ' \
  "$(authof "$(SA_NOW=$pin bash "$s/quota.sh" --fleet "$tmp/inst2.json")")"
# the window's edges, on a pinned clock: 86399 s old stands, exactly 86400 s old is expired
rec "$tmp/inst2.json" t3 "$(ts $((pin - 86399)))"
check "a T3-sourced failure 86399 s old stands" 'failed Provider is not authenticated.' \
  "$(authof "$(SA_NOW=$pin bash "$s/quota.sh" --fleet "$tmp/inst2.json")")"
rec "$tmp/inst2.json" t3 "$(ts $((pin - 86400)))"
check "a T3-sourced failure exactly 86400 s old is expired" 'ok ' \
  "$(authof "$(SA_NOW=$pin bash "$s/quota.sh" --fleet "$tmp/inst2.json")")"
rec "$tmp/inst2.json" t3 "$now"
check "a record that cannot be read is unknown, never a verdict" 'unknown could not read the recorded auth verdict' \
  "$(authof "$(SA_NOW=notanumber bash "$s/quota.sh" --fleet "$tmp/inst2.json")")"
rec "$tmp/inst2.json" command "$now"
check "a command-sourced recorded failure is cleared by a passing live command" 'ok ' \
  "$(authof "$(SA_NOW=$pin bash "$s/quota.sh" --fleet "$tmp/inst2.json")")"
rec "$tmp/inst2.json" - -
check "a legacy bare recorded failure (no source, no date) is cleared by a passing live command" 'ok ' \
  "$(authof "$(SA_NOW=$pin bash "$s/quota.sh" --fleet "$tmp/inst2.json")")"
rec "$tmp/inst2.json" t3 -
check "a T3-sourced failure with no date counts as expired" 'ok ' \
  "$(authof "$(SA_NOW=$pin bash "$s/quota.sh" --fleet "$tmp/inst2.json")")"
reset; sa_account claude b 0 "$claude_b"; sa_claude_auth b 1
rec "$tmp/inst2.json" command "$now"
check "a failing live command still reads failed over a stale record" 'failed auth command exited 1' \
  "$(authof "$(SA_NOW=$pin bash "$s/quota.sh" --fleet "$tmp/inst2.json")")"
reset; sa_account claude b 0 "$claude_b"

# an env value holding a newline stays one KEY=VALUE word: it never becomes the program `env` runs
reset; sa_account claude touch 0 "$claude_b"
jq -n '{providers: {claudeAgent_b: {driver: "claude", env: {CLAUDE_CONFIG_DIR: "/acct/x\ntouch"}, quota_command: "claude -p \"/usage\" --output-format json"}}}' > "$tmp/nl.json"
check "a newline in an env value does not replace the command" available "$(bash "$s/quota.sh" --fleet "$tmp/nl.json" | jq -r .providers.claudeAgent_b.status)"

# a Claude provider reads its own account: a leading ~ in env is expanded, and no env means the default
# account, not the caller's; Codex keeps the caller's environment
sa_fake_install "$tmp/bin"; reset; sa_claude_auth other 1
jq -n '{providers: {
  claudeAgent: {driver: "claude", env: {CLAUDE_CONFIG_DIR: "~/x"}, quota_command: "claude -p \"/usage\" --output-format json", auth_command: "claude auth status"},
  claudeAgent_b: {driver: "claude", quota_command: "claude -p \"/usage\" --output-format json", auth_command: "claude auth status"},
  codex: {driver: "codex", quota_command: "codex app-server"}}}' > "$tmp/home.json"
rm -f "$SA_FAKE/config-dirs"
out=$(HOME=/h CLAUDE_CONFIG_DIR=/other bash "$s/quota.sh" --fleet "$tmp/home.json")
check "each command sees its own config dir: HOME/x, none; Codex keeps the caller's" 'claude|/h/x claude|<unset> codex|/other' \
  "$(LC_ALL=C sort -u "$SA_FAKE/config-dirs" | tr '\n' ' ' | sed 's/ $//')"
check "the provider with no env passes its auth command under the default account" 'ok ok' \
  "$(jq -r '.providers | "\(.claudeAgent.auth) \(.claudeAgent_b.auth)"' <<<"$out")"

# an old-shaped file (keyed by CLI name, no env or auth command) still reads, with auth unknown
reset
out=$(Q)
check "an old-shaped provider reads as before, driver defaulting to its key" 'claude unknown' \
  "$(jq -r '.providers.claude | "\(.driver) \(.auth)"' <<<"$out")"
check "env on a provider that sets none is left to the caller's own" available "$(jq -r .providers.claude.status <<<"$out")"

# --- the fleet file's weekly_weight and floors ride the read; a read is saved per wake --------------
reset
jq -n '{five_hour_floor: 0.2, weekly_reserve: 0.1, providers: {
  big: {driver: "claude", weekly_weight: 3, models: {sonnet: "claude-sonnet-5-5"}, route: true, quota_command: "claude -p \"/usage\" --output-format json"},
  small: {driver: "claude", quota_command: "claude -p \"/usage\" --output-format json"}}}' > "$tmp/w.json"
out=$(bash "$s/quota.sh" --fleet "$tmp/w.json")
check "a provider's weekly_weight is carried to its answer, none where the entry sets none" '3 null' \
  "$(jq -r '.providers | "\(.big.weekly_weight) \(.small.weekly_weight)"' <<<"$out")"
check "a provider's models map and route allowance are carried for route to read, none where the entry sets none" '{"sonnet":"claude-sonnet-5-5"} true null null' \
  "$(jq -r '.providers | "\(.big.models | tojson) \(.big.route) \(.small.models) \(.small.route)"' <<<"$out")"
check "the fleet file's floors are carried as floors" '{"five_hour":0.2,"weekly_reserve":0.1}' "$(jq -c .floors <<<"$out")"
check "a fleet file with neither carries empty floors" '{}' "$(Q | jq -c .floors)"
jq -n '{providers: {big: {driver: "claude", weekly_weight: 0, quota_command: "x"}}}' > "$tmp/bw.json"
check_rc "a weekly_weight of 0 exits 2" 2 "$(bash "$s/quota.sh" --fleet "$tmp/bw.json" >/dev/null 2>&1; echo $?)"
jq -n '{weekly_reserve: 1.5, providers: {}}' > "$tmp/bw.json"
check_rc "a floor above 1 exits 2" 2 "$(bash "$s/quota.sh" --fleet "$tmp/bw.json" >/dev/null 2>&1; echo $?)"
check_rc "--save without --wake exits 2" 2 "$(bash "$s/quota.sh" --fleet "$fleet" --save "$tmp/sv.json" >/dev/null 2>&1; echo $?)"
check_rc "--wake without --save exits 2" 2 "$(bash "$s/quota.sh" --fleet "$fleet" --wake w1 >/dev/null 2>&1; echo $?)"

reset
SQ() { SA_NOW=$1 bash "$s/quota.sh" --fleet "$fleet" --save "$tmp/sv.json" --wake "$2"; }
t1=1793979000 t2=1793979600
out1=$(SQ $t1 wake-1)
check "a read takes its time from the clock" "$(date -u -d "@$t1" +%Y-%m-%dT%H:%M:%SZ) wake-1" "$(jq -r '"\(.read_at) \(.wake)"' <<<"$out1")"
sa_provider claude 0 "$(jq -cn '{type:"result", is_error:false, result:"Current session: 90% used · resets x\nCurrent week (all models): 90% used · resets y"}')"
out2=$(SQ $t2 wake-1)
check "a second launch of the same wake gets the saved read, later clock or not" "$out1" "$out2"
check "though the provider now reports less" 0.45 "$(jq -r '.providers.claude.buckets[] | select(.id == "week") | .remaining' <<<"$out2")"
out3=$(SQ $t2 wake-2)
check "the next wake reads again" "0.1 $(date -u -d "@$t2" +%Y-%m-%dT%H:%M:%SZ) wake-2" \
  "$(jq -r '"\(.providers.claude.buckets[] | select(.id == "week") | .remaining) \(.read_at) \(.wake)"' <<<"$out3")"
check "and replaces the saved file" wake-2 "$(jq -r .wake "$tmp/sv.json")"

finish
