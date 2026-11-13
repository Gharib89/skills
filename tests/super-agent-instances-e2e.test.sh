#!/usr/bin/env bash
# super-agent's provider-instance chain end to end over the fake provider CLIs
# (tests/super-agent-fake.sh): setup writes a fleet file from a saved
# `orchestrator_capabilities` answer, quota reads each instance's own account,
# and route picks the healthy instance, whose id is the launch's `instanceId`.
# An instance that T3 reports signed out, or whose weekly bucket is empty, is
# never picked while another instance is healthy.
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

week() { # <used percent>: a Claude `/usage` print
  jq -cn --arg r "$(printf 'Current session: 2%% used · resets x\nCurrent week (all models): %s%% used · resets y' "$1")" '{result: $r}'
}
# launch <size>: the chain a launch runs, and the instance, model and options it would send
launch() {
  bash "$s/quota.sh" --fleet "$fleet" > "$tmp/quota.json"
  bash "$s/route.sh" --size "$1" --quota "$tmp/quota.json" | jq -c '{instance_id, model, options}'
}
chain() { # <capabilities file>: a fresh fleet file written by setup from the saved answer
  rm -f "$fleet" "$SA_FAKE/calls"
  sa_machine laptop 12 32768
  sa_provider claude 0 "$(week 5)"; sa_provider codex 0 '{}'; sa_provider agy 0 '{}'
  sa_github alice
  bash "$s/setup.sh" --fleet "$fleet" --write --name laptop --instances "$1" >/dev/null
}

# --- instance A is signed out in T3, B is healthy: B launches ---------------------------------------
sa_instances "$tmp/unauth.json" claudeAgent:claudeAgent:unauth claudeAgent_b:claudeAgent:home=/acct/b
chain "$tmp/unauth.json"
sa_account claude b 0 "$(week 20)"
check "setup recorded the signed-out instance as auth failed" failed "$(jq -r '.providers.claudeAgent.auth' "$fleet")"
check "the launch goes to the healthy instance, with its model and effort" '{"instance_id":"claudeAgent_b","model":"opus","options":[{"id":"effort","value":"medium"}]}' "$(launch M)"

# --- both signed in, A at 0% weekly, B healthy: B launches ------------------------------------------
sa_instances "$tmp/empty.json" claudeAgent:claudeAgent:home=/acct/a claudeAgent_b:claudeAgent:home=/acct/b
chain "$tmp/empty.json"
sa_account claude a 0 "$(week 100)"; sa_account claude b 0 "$(week 20)"
check "an instance at 0% weekly is skipped for the healthy one" claudeAgent_b "$(launch S | jq -r .instance_id)"

# --- A recovers: the instance with the most weekly quota left wins -------------------------------------
sa_account claude a 0 "$(week 10)"
check "the instance with more weekly quota left wins" claudeAgent "$(launch S | jq -r .instance_id)"

# --- every instance unusable: no instance is named, so the caller escalates ---------------------------
sa_account claude a 0 "$(week 100)"; sa_account claude b 0 "$(week 100)"
check "with no usable instance the launch names none" null "$(launch S | jq -r .instance_id)"

finish
