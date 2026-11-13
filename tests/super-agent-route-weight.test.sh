#!/usr/bin/env bash
# super-agent's `route` ranking by weekly headroom (weekly remaining times the
# instance's weekly_weight), the 5 hour floor and the weekly reserve, driven
# through its command line over saved `quota` output.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
R() { bash "$s/route.sh" "$@"; }
source tests/super-agent-route-lib.sh
unknown() { jq -cn '{providers: {claude: {status: "unknown", reason: "quota command exited 1", buckets: []}}}' > "$tmp/q.json"; }
tier() { jq -r '"\(.tier.model) \(.tier.effort) ask=\(.ask)"'; }

# --- weekly headroom: the weekly remaining times the entry's weekly_weight --------------------------
w() { jq -r '"\(.instance_id) \(.reason)"'; }
quotas "$(inst big claude 0.4 ok '{"weekly_weight":3}')" "$(inst small claude 0.6 ok)"
check "weight 3 at 0.4 outranks weight 1 at 0.6" big "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst big claude 0.4 ok '{"weekly_weight":1}')" "$(inst small claude 0.6 ok)"
check "equal weights rank by the fraction, as before" small "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst big claude 0.4 ok)" "$(inst small claude 0.6 ok)"
check "no weight at all is weight 1" small "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst big claude 0.4 ok '{"weekly_weight":0}')"
res=$(R --size S --quota "$tmp/q.json" 2>/dev/null); rc=$?
check_rc "a weight of 0 is refused" 2 "$rc"
check "by name" "$tmp/q.json: every weekly_weight must be a number above 0" "$(jq -r .error <<<"$res")"
quotas "$(inst a claude 0.4 ok)"; jq '. + {floors: {five_hour: 2}}' "$tmp/q.json" > "$tmp/q2.json"
check_rc "a floor above 1 is refused" 2 "$(R --size S --quota "$tmp/q2.json" >/dev/null 2>&1; echo $?)"

# --- the 5 hour floor and the weekly reserve ---------------------------------------------------------
b5() { jq -cn --argjson s "$1" --argjson w "$2" '{buckets: [{id: "session", window: "5h", remaining: $s, resets: "x"}, {id: "week", window: "weekly", remaining: $w, resets: "x"}]}'; }
quotas "$(inst a claude 0.9 ok "$(b5 0.05 0.9)")" "$(inst b claude 0.3 ok "$(b5 0.8 0.3)")"
res=$(R --size S --quota "$tmp/q.json")
check "an instance under the 5 hour floor (default 0.1) is skipped, the other wins" b "$(jq -r .instance_id <<<"$res")"
check "and the reason names the 5 hour floor and the instance" "b the default tier (skipped: a 5 hour bucket under the 5 hour floor 0.1)" "$(jq -r '"\(.instance_id) \(.reason)"' <<<"$res")"
quotas "$(inst a claude 0.9 ok "$(b5 0.1 0.9)")"
check "a 5 hour bucket exactly at the floor is not under it" a "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst a claude 0.9 ok "$(b5 0.3 0.9)")"; jq '. + {floors: {five_hour: 0.5}}' "$tmp/q.json" > "$tmp/q2.json"
res=$(R --size S --quota "$tmp/q2.json")
check "the fleet file's floor replaces the default" "null no instance can launch: a 5 hour bucket under the 5 hour floor 0.5" "$(w <<<"$res")"
quotas "$(inst a claude 0.04 ok "$(b5 0.9 0.04)")" "$(inst b claude 0.3 ok "$(b5 0.8 0.3)")"
res=$(R --size S --quota "$tmp/q.json")
check "an instance under the weekly reserve (default 0.05) is skipped and the reason names it" "b the default tier (skipped: a weekly under the weekly reserve 0.05)" "$(w <<<"$res")"
quotas "$(inst a claude 0.04 ok "$(b5 0.9 0.04)")"; jq '. + {floors: {weekly_reserve: 0.02}}' "$tmp/q.json" > "$tmp/q2.json"
check "the fleet file's reserve replaces the default" a "$(R --size S --quota "$tmp/q2.json" | jq -r .instance_id)"
quotas "$(inst a claude 0.04 ok "$(b5 0.05 0.04)")" "$(inst b claude 0.9 ok "$(b5 0.01 0.9)")"
res=$(R --size S --quota "$tmp/q.json"); rc=$?
check_rc "every candidate skipped still answers, exit 0" 0 "$rc"
check "with no instance and both reasons" "null no instance can launch: a weekly under the weekly reserve 0.05, b 5 hour bucket under the 5 hour floor 0.1" "$(w <<<"$res")"
check "and the default tier, no ask" "sonnet medium ask=false" "$(tier <<<"$res")"
quotas "$(inst a claude null ok '{"buckets":[]}')" "$(inst b claude 0.5 ok "$(b5 0.5 0.5)")"
check "an instance with no measured bucket is never skipped on a floor" b "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
unknown
res=$(R --size S --raise 1 --quota "$tmp/q.json")
check "an unknown quota still routes and never asks" "claude sonnet medium ask=false" "$(jq -r '"\(.instance_id) \(.tier.model) \(.tier.effort) ask=\(.ask)"' <<<"$res")"

quotas "$(inst a claude 0.05 ok "$(b5 0.9 0.05)")"
check "a weekly bucket exactly at the reserve is not under it" a "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst a claude 0 ok "$(b5 0.9 0)")"; jq '. + {floors: {weekly_reserve: 0}}' "$tmp/q.json" > "$tmp/q2.json"
res=$(R --size S --quota "$tmp/q2.json")
check "a weekly bucket at 0 reads weekly at 0 even with a reserve of 0" "null no instance can launch: a weekly at 0" "$(w <<<"$res")"
quotas "$(inst a claude 0.5 ok '{"weekly_weight":-1}')"
check_rc "a negative weight is refused" 2 "$(R --size S --quota "$tmp/q.json" >/dev/null 2>&1; echo $?)"

finish
