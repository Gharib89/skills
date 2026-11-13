#!/usr/bin/env bash
# super-agent's `route` for the `cursor` and `grok` instances: no usage read, so
# a last resort the owner must allow (`route: true`) or name (`--instance`),
# never ahead of a measured instance.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
R() { bash "$s/route.sh" "$@"; }
source tests/super-agent-route-lib.sh

# --- cursor and grok: no usage read, so a last resort (or the owner's pick), never ahead of a measured instance ----
quotas "$(inst claudeAgent claude 0.3 ok)" "$(inst grok grok null ok)"
check "an unallowed grok instance is not picked while a Claude instance can launch" claudeAgent "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude 0.3 ok)" "$(inst grok grok null ok '{"route": true}')"
check "an allowed unknown-quota grok instance still loses to a Claude instance that can launch" claudeAgent "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude 0.9 failed)" "$(inst grok grok null ok '{"route": true}')" "$(inst cursor cursor null ok '{"route": true}')"
res=$(R --size S --quota "$tmp/q.json")
check "with every Claude instance signed out, the first signed-in last-resort instance launches, on its own default model" 'cursor null null' \
  "$(jq -r '"\(.instance_id) \(.model) \(.options | tostring | if . == "null" then "null" else . end)"' <<<"$res")"
check "and the reason names the last resort" 'no routable instance has a measured quota: last resort' "$(jq -r .reason <<<"$res")"
quotas "$(inst claudeAgent claude 0 ok)" "$(inst grok grok null ok '{"route": true, "models": {"sonnet": "grok-4.7"}}')"
check "an exhausted Claude instance leaves the last resort, on the model the owner mapped for the tier" 'grok grok-4.7' "$(R --size S --quota "$tmp/q.json" | jq -r '"\(.instance_id) \(.model)"')"
quotas "$(inst claudeAgent claude 0.9 failed)" "$(inst grok grok null failed '{"route": true}')" "$(inst cursor cursor null ok '{"route": true}')"
check "a last-resort instance whose auth failed is skipped" cursor "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude 0.9 failed)" "$(inst grok grok null failed '{"route": true}')"
res=$(R --size S --quota "$tmp/q.json")
check "none signed in: a null instance, the reason naming each" 'null no instance can launch: claudeAgent auth failed, grok auth failed' "$(jq -r '"\(.instance_id) \(.reason)"' <<<"$res")"
quotas "$(inst claudeAgent claude 0.9 ok)" "$(inst grok grok null ok)"
res=$(R --size S --instance grok --quota "$tmp/q.json")
check "the owner naming the instance launches it though a Claude instance has room" 'grok owner named the instance' "$(jq -r '"\(.instance_id) \(.reason)"' <<<"$res")"
check "a named Claude instance routes as usual, tier included" 'claudeAgent sonnet medium' "$(R --size S --instance claudeAgent --quota "$tmp/q.json" | jq -r '"\(.instance_id) \(.model) \(.tier.effort)"')"
check "a named instance the quota file lacks is a null instance with the reason" 'null no instance can launch: nope is not a routable instance in the quota read' \
  "$(R --size S --instance nope --quota "$tmp/q.json" | jq -r '"\(.instance_id) \(.reason)"')"
quotas "$(inst claudeAgent claude 0.9 ok)" "$(inst grok grok null failed)"
check "a named instance whose auth failed is a null instance" 'null' "$(R --size S --instance grok --quota "$tmp/q.json" | jq -r .instance_id)"
check "a named instance at 0 weekly is a null instance" null "$( quotas "$(inst claudeAgent claude 0 ok)"; R --size S --instance claudeAgent --quota "$tmp/q.json" | jq -r .instance_id)"

quotas "$(inst claudeAgent claude 0.9 failed)" "$(inst grok grok null ok)" "$(inst cursor cursor null ok)"
res=$(R --size S --quota "$tmp/q.json")
check "with Claude signed out, a cursor or grok entry without route true is not picked: a null instance" 'null' "$(jq -r .instance_id <<<"$res")"
check "and the reason names the Claude instance that cannot launch" 'no instance can launch: claudeAgent auth failed' "$(jq -r .reason <<<"$res")"
quotas "$(inst grok grok null ok)"
check "with only an unallowed entry, the reason names the instances the owner allowed" 'no instance can launch: no claude instance, and no pi, cursor or grok instance the owner allowed, in the quota read' "$(R --size S --quota "$tmp/q.json" | jq -r .reason)"
quotas "$(inst claudeAgent claude 0.9 failed)" "$(inst cursor cursor null ok '{"route": true}')"
check "the same cursor entry with route true is the last resort" cursor "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude 0.9 failed)" "$(inst cursor cursor null ok '{"route": false}')"
check "route false is the default: not picked" null "$(R --size S --quota "$tmp/q.json" | jq -r .instance_id)"
quotas "$(inst claudeAgent claude 0.9 ok)" "$(inst cursor cursor null ok)"
check "the owner naming a cursor entry routes to it with route unset" 'cursor owner named the instance' "$(R --size S --instance cursor --quota "$tmp/q.json" | jq -r '"\(.instance_id) \(.reason)"')"

finish
