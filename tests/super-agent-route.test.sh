#!/usr/bin/env bash
# super-agent's `route`, driven through its command line over saved `quota`
# output: the Size label picks the starting tier, a raise climbs the ladder, the
# owner is asked only for a tier above the default when that bucket's weekly
# remaining is under 50%, and an unknown quota falls back to the default tier
# without asking. A bounded text job goes to agy, its Claude group the overflow
# while Claude Code's weekly bucket is low.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
R() { bash "$s/route.sh" "$@"; }

# quota <claude weekly> <agy claude-group weekly>: a `quota` answer
quota() {
  jq -cn --argjson c "$1" --argjson a "$2" '{providers: {
    claude: {status: "available", reason: null, buckets: [{id: "session", window: "5h", remaining: 1, resets: "x"}, {id: "week", window: "weekly", remaining: $c, resets: "x"}]},
    agy: {status: "available", reason: null, buckets: [{id: "gemini-weekly", group: "Gemini Models", window: "weekly", remaining: 0.9, resets: "x"}, {id: "3p-weekly", group: "Claude and GPT models", window: "weekly", remaining: $a, resets: "x"}]}}}' > "$tmp/q.json"
}
unknown() { jq -cn '{providers: {claude: {status: "unknown", reason: "quota command exited 1", buckets: []}}}' > "$tmp/q.json"; }
tier() { jq -r '"\(.tier.model) \(.tier.effort) ask=\(.ask)"'; }

# --- the contract every script keeps -----------------------------------------------
out=$(bash "$s/route.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: route" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
usage=$(sed -n 1p <<<"$out")
quota 0.9 0.9
refused() { # <case> <args>...: a malformed call exits 2
  local c=$1; shift
  bash "$s/route.sh" "$@" >/dev/null 2>&1; check_rc "$c exits 2" 2 "$?"
}
refused "an unknown flag" --bogus
refused "no quota" --size M
refused "a size that is not a label" --size XXL --quota "$tmp/q.json"
refused "a raise that is not a number" --size M --raise x --quota "$tmp/q.json"
refused "a job that is not text" --job poem --quota "$tmp/q.json"
refused "a size with a job" --size M --job text --quota "$tmp/q.json"
refused "neither size nor job" --quota "$tmp/q.json"
refused "a quota file that is missing" --size M --quota "$tmp/none.json"
refused "--claude with a size" --size M --claude --quota "$tmp/q.json"
quota 0.9 0.9
check "a bad call answers the usage line" "$usage" "$(bash "$s/route.sh" --bogus 2>/dev/null | jq -r .error)"
printf 'not json\n' > "$tmp/bad.json"
check_rc "quota output that is not JSON exits 2" 2 "$(bash "$s/route.sh" --size M --quota "$tmp/bad.json" >/dev/null 2>&1; echo $?)"

# --- a quota file of the wrong shape is refused by name, never routed on ---------------------------
echo '{"providers":[]}' > "$tmp/shape.json"
out=$(R --size M --raise 1 --quota "$tmp/shape.json" 2>/dev/null); rc=$?
check_rc "providers that are not an object exit 2" 2 "$rc"
check "and name the file and field" "$tmp/shape.json: providers must be an object" "$(jq -r .error <<<"$out")"
echo '{"providers":{"claude":{"buckets":[{"id":"week","window":"weekly","remaining":"0.1"}]}}}' > "$tmp/shape.json"
out=$(R --size M --raise 1 --quota "$tmp/shape.json" 2>/dev/null); rc=$?
check_rc "a remaining that is a string exits 2, not an unasked raise" 2 "$rc"
check "and says which field" "$tmp/shape.json: every bucket's remaining must be a number" "$(jq -r .error <<<"$out")"
check_rc "the same for a job" 2 "$(R --job text --claude --quota "$tmp/shape.json" >/dev/null 2>&1; echo $?)"

# --- the Size label sets the starting tier -------------------------------------------
quota 0.9 0.9
check "XS starts on Sonnet low" "sonnet low ask=false" "$(R --size XS --quota "$tmp/q.json" | tier)"
check "S starts on Sonnet low" "sonnet low ask=false" "$(R --size S --quota "$tmp/q.json" | tier)"
check "M starts on Sonnet medium" "sonnet medium ask=false" "$(R --size M --quota "$tmp/q.json" | tier)"
check "L starts on Sonnet high" "sonnet high ask=false" "$(R --size L --quota "$tmp/q.json" | tier)"
check "XL starts on Opus high" "opus high ask=false" "$(R --size XL --quota "$tmp/q.json" | tier)"
check "the size and raise are echoed with the default" '{"size":"M","raise":0,"default":{"model":"sonnet","effort":"medium"}}' \
  "$(R --size M --quota "$tmp/q.json" | jq -c '{size, raise, default}')"

# --- a raise climbs one step per stall or hard finding, and stops at the top ----------------
check "a raise of 1 takes M to Sonnet high" "sonnet high ask=false" "$(R --size M --raise 1 --quota "$tmp/q.json" | tier)"
check "a raise of 2 takes S to Sonnet high" "sonnet high ask=false" "$(R --size S --raise 2 --quota "$tmp/q.json" | tier)"
check "a raise of 1 takes L to Opus high" "opus high ask=false" "$(R --size L --raise 1 --quota "$tmp/q.json" | tier)"
check "a raise past the top stays on Opus high" "opus high ask=false" "$(R --size XL --raise 3 --quota "$tmp/q.json" | tier)"

# --- the owner is asked only above the default with a weekly bucket under 50% ----------------
quota 0.49 0.9
check "above the default, weekly under 50%: ask, and launch the default meanwhile" "sonnet medium ask=true" "$(R --size M --raise 1 --quota "$tmp/q.json" | tier)"
check "the answer names the tier wanted and the bucket" '{"wanted":{"model":"sonnet","effort":"high"},"bucket":{"provider":"claude","id":"week","remaining":0.49}}' \
  "$(R --size M --raise 1 --quota "$tmp/q.json" | jq -c '{wanted, bucket}')"
check "at the default, weekly under 50%: no ask" "sonnet medium ask=false" "$(R --size M --quota "$tmp/q.json" | tier)"
check "XL's default Opus high at weekly under 50%: no ask" "opus high ask=false" "$(R --size XL --quota "$tmp/q.json" | tier)"
quota 0.5 0.9
check "above the default, weekly at exactly 50%: no ask" "sonnet high ask=false" "$(R --size M --raise 1 --quota "$tmp/q.json" | tier)"
quota 0.51 0.9
check "above the default, weekly above 50%: no ask" "sonnet high ask=false" "$(R --size M --raise 1 --quota "$tmp/q.json" | tier)"
quota 0.1 0.9
check "the session bucket does not decide it, only the weekly one" "sonnet medium ask=true" "$(R --size M --raise 1 --quota "$tmp/q.json" | tier)"

# --- an unknown quota falls back to the default tier without asking ------------------------------
unknown
res=$(R --size M --raise 1 --quota "$tmp/q.json"); rc=$?
check_rc "an unknown quota still routes, exit 0" 0 "$rc"
check "the default tier, no ask" "sonnet medium ask=false" "$(tier <<<"$res")"
check "the answer says why" "quota unknown: default tier" "$(jq -r .reason <<<"$res")"
jq -cn '{providers: {}}' > "$tmp/q.json"
check "a quota with no claude provider is the same" "sonnet medium ask=false" "$(R --size M --raise 1 --quota "$tmp/q.json" | tier)"

# --- a bounded text job goes to agy, Claude's group the overflow ---------------------------------
quota 0.9 0.9
check "a text job goes to agy on the Gemini group" '{"driver":"agy","group":"gemini","model":"gemini-3.8-flash-medium"}' \
  "$(R --job text --quota "$tmp/q.json" | jq -c '{driver, group, model}')"
quota 0.1 0.9
check "a text job stays on Gemini however low Claude Code is" gemini "$(R --job text --quota "$tmp/q.json" | jq -r .group)"
check "a job that wants Claude stays on Claude Code while its weekly is not low" claude \
  "$(quota 0.9 0.9; R --job text --claude --quota "$tmp/q.json" | jq -r .driver)"
check "and overflows to agy's Claude group when Claude Code's weekly is under 50%" '{"driver":"agy","group":"claude","model":"claude-sonnet-4-6"}' \
  "$(quota 0.4 0.9; R --job text --claude --quota "$tmp/q.json" | jq -c '{driver, group, model}')"
check "not when agy's Claude group is itself under 50%" claude \
  "$(quota 0.4 0.3; R --job text --claude --quota "$tmp/q.json" | jq -r .driver)"
unknown
check "nor when quota is unknown" claude "$(R --job text --claude --quota "$tmp/q.json" | jq -r .driver)"
check "an unknown quota leaves a plain text job on agy Gemini" gemini "$(R --job text --quota "$tmp/q.json" | jq -r .group)"

# --- the launch instance: route picks the T3 instance with the most quota in the tier's driver ----
# inst <id> <driver> <weekly|null> <auth> [extra json]: one provider entry of a `quota` answer
inst() {
  jq -cn --arg id "$1" --arg d "$2" --argjson w "$3" --arg a "$4" --argjson x "${5:-{\}}" '{($id): ({driver: $d, status: (if $w == null then "unknown" else "available" end),
    reason: null, auth: $a, auth_reason: (if $a == "failed" then "auth command exited 1" else null end),
    buckets: (if $w == null then [] else [{id: "week", window: "weekly", remaining: $w, resets: "x"}] end)} + $x)}'
}
quotas() { jq -cn --argjson p "$(jq -cs 'add' <<<"$*")" '{providers: $p}' > "$tmp/q.json"; }
pick() { jq -r '"\(.instance_id) \(.model) \(.tier.effort) ask=\(.ask)"'; }

quotas "$(inst claudeAgent claude 0.9 ok)"
res=$(R --size M --quota "$tmp/q.json")
check "the answer names the instance, the model to send and its launch options" 'claudeAgent sonnet [{"id":"effort","value":"medium"}]' \
  "$(jq -r '"\(.instance_id) \(.model) \(.options | tostring)"' <<<"$res")"
quotas "$(inst claudeAgent claude 0.3 ok)" "$(inst claudeAgent_b claude 0.8 ok)"
check "two Claude instances: the one with the most weekly quota left" "claudeAgent_b sonnet medium ask=false" "$(R --size M --quota "$tmp/q.json" | pick)"
quotas "$(inst claudeAgent claude 0.9 failed)" "$(inst claudeAgent_b claude 0.2 ok)"
res=$(R --size M --quota "$tmp/q.json")
check "an instance whose auth failed is skipped, however much quota it shows" "claudeAgent_b sonnet medium ask=false" "$(pick <<<"$res")"
quotas "$(inst claudeAgent claude 0 ok)" "$(inst claudeAgent_b claude 0.2 ok)"
check "an instance at 0 weekly is skipped" claudeAgent_b "$(R --size M --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst a claude 0.5 ok)" "$(inst b claude 0.5 ok)"
check "a tie goes to the first by name" a "$(R --size M --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude 0.5 unknown)" "$(inst claudeAgent_b claude 0.1 ok)"
check "an unknown auth is no reason to skip" claudeAgent "$(R --size M --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude null ok)" "$(inst claudeAgent_b claude 0.1 ok)"
check "a measured bucket beats an unmeasured one" claudeAgent_b "$(R --size M --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude 0.9 failed)" "$(inst claudeAgent_b claude 0 ok)"
res=$(R --size M --raise 1 --quota "$tmp/q.json"); rc=$?
check_rc "no instance left still answers, exit 0" 0 "$rc"
check "with a null instance and the reason, for the caller to escalate" 'null no instance can launch: claudeAgent auth failed, claudeAgent_b weekly at 0' \
  "$(jq -r '"\(.instance_id) \(.reason)"' <<<"$res")"
check "and the default tier, no ask" "sonnet medium ask=false" "$(tier <<<"$res")"

# the raise-ask rule reads the chosen instance's bucket
quotas "$(inst claudeAgent claude 0.45 ok)" "$(inst claudeAgent_b claude 0.4 ok)"
res=$(R --size M --raise 1 --quota "$tmp/q.json")
check "the weekly bucket asked about is the chosen instance's" 'claudeAgent true {"provider":"claudeAgent","id":"week","remaining":0.45}' \
  "$(jq -r '"\(.instance_id) \(.ask) \(.bucket | tostring)"' <<<"$res")"

# a Pi instance: a candidate only when the owner allowed it, its model the tier's mapping
pi_models='{"route": true, "models": {"sonnet": "antigravity/claude-sonnet-4-6", "opus": "antigravity/claude-opus-4-6"}}'
pi_buckets='{"buckets": [{"id": "3p-weekly", "group": "Claude and GPT models", "window": "weekly", "remaining": 0.9, "resets": "x"}, {"id": "gemini-weekly", "group": "Gemini Models", "window": "weekly", "remaining": 0.1, "resets": "x"}]}'
quotas "$(inst claudeAgent claude 0.3 ok)" "$(inst pi pi 0.9 ok "$(jq -cn --argjson a "$pi_models" --argjson b "$pi_buckets" '$a + $b')")"
res=$(R --size M --quota "$tmp/q.json")
check "a Pi instance with more Claude-group quota takes the launch, on its mapped model" 'pi antigravity/claude-sonnet-4-6 [{"id":"thinking","value":"high"}]' \
  "$(jq -r '"\(.instance_id) \(.model) \(.options | tostring)"' <<<"$res")"
check "its tier is still the size's" "sonnet medium ask=false" "$(tier <<<"$res")"
res=$(R --size XL --quota "$tmp/q.json")
check "the Opus rung maps to the Pi instance's Opus model" 'pi antigravity/claude-opus-4-6' "$(jq -r '"\(.instance_id) \(.model)"' <<<"$res")"
quotas "$(inst claudeAgent claude 0.3 ok)" "$(inst pi pi 0.9 ok "$(jq -cn --argjson b "$pi_buckets" '{route: false} + $b')")"
check "a Pi instance the owner did not allow is never picked" claudeAgent "$(R --size M --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude 0.5 ok)" "$(inst pi pi 0.5 ok "$(jq -cn --argjson a "$pi_models" '$a + {buckets: [{id: "3p-weekly", group: "Claude and GPT models", window: "weekly", remaining: 0.5, resets: "x"}]}')")"
check "a tie between a Claude instance and a Pi instance goes to Claude" claudeAgent "$(R --size M --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude 0.9 failed)" "$(inst pi pi 0.2 ok "$(jq -cn --argjson a "$pi_models" --argjson b "$pi_buckets" '$a + $b | .buckets[0].remaining = 0.2')")"
check "with Claude unauthenticated, the Pi instance is the launch" pi "$(R --size M --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude 0.9 failed)" "$(inst pi pi 0.9 ok '{"route": true, "models": {"sonnet": "antigravity/claude-sonnet-4-6"}, "buckets": [{"id": "3p-weekly", "group": "Claude and GPT models", "window": "weekly", "remaining": 0.9, "resets": "x"}]}')"
check "a Pi instance with no model for the tier cannot take it" 'null' "$(R --size XL --quota "$tmp/q.json" | jq -r .instance_id)"

# an old-shaped quota file (keyed claude) routes as before, instance `claude`
quota 0.9 0.9
check "an old-shaped file names its key as the instance" 'claude sonnet' "$(R --size M --quota "$tmp/q.json" | jq -r '"\(.instance_id) \(.model)"')"

# --- the owner's yes: wanted_model and wanted_options are what to send for the raised tier ------------
quotas "$(inst claudeAgent claude 0.3 ok)"
res=$(R --size M --raise 1 --quota "$tmp/q.json")
check "an ask names the raised tier's model and options beside the default's" 'true medium sonnet [{"id":"effort","value":"high"}] sonnet [{"id":"effort","value":"medium"}]' \
  "$(jq -r '"\(.ask) \(.tier.effort) \(.wanted_model) \(.wanted_options | tostring) \(.model) \(.options | tostring)"' <<<"$res")"
quotas "$(inst pi pi 0.3 ok "$(jq -cn --argjson a "$pi_models" --argjson b "$pi_buckets" '$a + $b | .buckets[0].remaining = 0.3')")"
res=$(R --size L --raise 1 --quota "$tmp/q.json")
check "on a Pi instance the raised tier maps to its own model id" 'pi antigravity/claude-sonnet-4-6 antigravity/claude-opus-4-6' \
  "$(jq -r '"\(.instance_id) \(.model) \(.wanted_model)"' <<<"$res")"

# --- a Claude text job reads the Claude instances, not a key named claude ----------------------------------
agy_q='{"agy": {"driver": "agy", "buckets": [{"id": "3p-weekly", "group": "Claude and GPT models", "window": "weekly", "remaining": 0.9, "resets": "x"}]}}'
job() { R --job text --claude --quota "$tmp/q.json" | jq -r '"\(.driver) \(.group)"'; }
quotas "$(inst claudeAgent claude 0.3 ok)" "$agy_q"
check "every Claude instance under 50%: the job overflows to agy's Claude group" "agy claude" "$(job)"
quotas "$(inst claudeAgent claude 0.3 ok)" "$(inst claudeAgent_b claude 0.8 ok)" "$agy_q"
check "one Claude instance with room keeps the job on Claude Code" "claude null" "$(job)"
quotas "$(inst claudeAgent claude 0.3 ok)" "$(inst claudeAgent_b claude 0.8 failed)" "$agy_q"
check "an instance that is signed out gives no room" "agy claude" "$(job)"

finish
