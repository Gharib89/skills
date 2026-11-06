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

finish
