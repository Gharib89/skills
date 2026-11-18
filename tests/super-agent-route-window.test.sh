#!/usr/bin/env bash
# super-agent's `route` in the last hour of a weekly window: an instance whose
# weekly bucket resets within 60 min has its weekly reserve at 0, so queued work
# spends the last of that quota, while its 5 hour floor still holds. Driven
# through the command line over saved `quota` output, `SA_NOW` pinning the clock.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
R() { SA_NOW=1800000000 bash "$s/route.sh" "$@"; }
source tests/super-agent-route-lib.sh

# b <5h remaining> <weekly remaining> <weekly resets_at>: one Claude instance's buckets
b() { jq -cn --argjson s "$1" --argjson w "$2" --argjson r "$3" '{buckets: [{id: "session", window: "5h", remaining: $s, resets: "x", resets_at: 1800009000},
  {id: "week", window: "weekly", remaining: $w, resets: "x", resets_at: $r}]}'; }
pick() { R --size S --quota "$tmp/q.json" | jq -r '"\(.instance_id) \(.reason)"'; }

# --- the weekly reserve drops to 0 inside the last hour -----------------------------------------
quotas "$(inst a claude 0.02 ok "$(b 0.9 0.02 1800003000)")"
check "a weekly bucket under the reserve that resets in 50 min launches" "a the default tier" "$(pick)"
quotas "$(inst a claude 0.02 ok "$(b 0.9 0.02 1800003600)")"
check "a reset exactly 60 min away is inside the last hour" "a the default tier" "$(pick)"
quotas "$(inst a claude 0.02 ok "$(b 0.9 0.02 1800003601)")"
check "a reset 60 min and 1 s away keeps the reserve" \
  "null no instance can launch: a weekly under the weekly reserve 0.05" "$(pick)"
quotas "$(inst a claude 0.02 ok "$(b 0.9 0.02 1799999000)")"
check "a reset already past keeps the reserve" \
  "null no instance can launch: a weekly under the weekly reserve 0.05" "$(pick)"
quotas "$(inst a claude 0.02 ok "$(b 0.9 0.02 null)")"
check "a bucket with no reset time keeps the reserve" \
  "null no instance can launch: a weekly under the weekly reserve 0.05" "$(pick)"
quotas "$(inst a claude 0 ok "$(b 0.9 0 1800003000)")"
check "a weekly bucket at 0 is still skipped in the last hour" "null no instance can launch: a weekly at 0" "$(pick)"
quotas "$(inst a claude 0.02 ok "$(b 0.9 0.02 1800003000)")"; jq '. + {floors: {weekly_reserve: 0.5}}' "$tmp/q.json" > "$tmp/q2.json"; mv "$tmp/q2.json" "$tmp/q.json"
check "a reserve the fleet file raised drops to 0 too" "a the default tier" "$(pick)"

# --- the 5 hour floor holds inside the last hour --------------------------------------------------
quotas "$(inst a claude 0.02 ok "$(b 0.05 0.02 1800003000)")"
check "a 5 hour bucket under its floor is skipped inside the last hour" \
  "null no instance can launch: a 5 hour bucket under the 5 hour floor 0.1" "$(pick)"
quotas "$(inst a claude 0.9 ok "$(b 0.05 0.9 1800003000)")" "$(inst b claude 0.3 ok "$(b 0.8 0.3 1800500000)")"
check "and the other instance wins, the floor named" "b the default tier (skipped: a 5 hour bucket under the 5 hour floor 0.1)" "$(pick)"

finish
