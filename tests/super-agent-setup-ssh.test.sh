#!/usr/bin/env bash
# super-agent's `setup` and the machines' ssh strings (#1382), over fake probes and a
# fake `ssh` on PATH (tests/super-agent-fake.sh): a linked machine's string is
# proposed from its T3 host name and recorded only after a key-only test passes, a
# new machine whose test fails is not added and is named, `--ssh` picks the string,
# and `--check-only` adds a machine that is checked and never placed on.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/super-agent-setup-lib.sh
reset() {
  rm -f "$fleet" "$SA_FAKE/calls" "$SA_FAKE/environments.json" "$SA_FAKE/gh-auth.json"
  sa_machine laptop 12 32768
  sa_provider claude 0 "$claude_ok"; sa_provider codex 0 "$codex_ok"; sa_provider agy 0 "$agy_ok"
  sa_environments '[]'; sa_github alice
}

# --- every linked machine carries a key-only tested ssh string (#1382) ---------------------
reset
sa_environments '[{"environmentId":"env-box","label":"box","urls":["https://box.tail.ts.net:8443"],"status":"reachable"},{"environmentId":"env-new","label":"new","urls":["https://new.tail.ts.net:8443"],"status":"unreachable"}]'
sa_ssh new.tail.ts.net 255 '' $'No ED25519 host key is known for new.tail.ts.net and you have requested strict checking.\nHost key verification failed.'
out=$(P --name laptop); rc=$?
check_rc "a failed ssh test still exits 0" 0 "$rc"
check "a linked machine's ssh string is proposed from its own T3 host name, and recorded when its test passes" box.tail.ts.net "$(jq -r .fleet.machines.box.ssh <<<"$out")"
check "the test is key-only, never accepts a new host key, and runs nothing but true" 1 \
  "$(grep -c '^ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=6 box.tail.ts.net true$' "$SA_FAKE/calls")"
check "a linked machine whose test fails is not added" null "$(jq -c .fleet.machines.new <<<"$out")"
check "and is refused by name, an unknown host key as unknown-host-key" '[{"machine":"new","ssh":"new.tail.ts.net","reason":"unknown-host-key"}]' "$(jq -c .ssh_refused <<<"$out")"
sa_ssh new.tail.ts.net 255 '' 'ribo@new.tail.ts.net: Permission denied (publickey).'
check "any other failure carries ssh's own reason" 'ribo@new.tail.ts.net: Permission denied (publickey).' "$(P --name laptop | jq -r '.ssh_refused[0].reason')"
out=$(S --name laptop --ssh new=gharib@new --write)
check "--ssh names the string to test instead, the saved-machines hint the owner picked" "gharib@new []" "$(jq -r '"\(.fleet.machines.new.ssh) \(.ssh_refused | tostring)"' <<<"$out")"
sa_ssh gharib@new 255 '' 'ssh: connect to host new port 22: Connection timed out'
out=$(P --name laptop)
check "a machine already in the file whose test now fails keeps its entry and string" "gharib@new env-new" "$(jq -r '.fleet.machines.new | "\(.ssh) \(.environment_id)"' <<<"$out")"
check "and is still named as refused" "new ssh: connect to host new port 22: Connection timed out" "$(jq -r '.ssh_refused[] | "\(.machine) \(.reason)"' <<<"$out")"
check "an --ssh for no linked machine is ignored and named" '--ssh typo: no linked machine has that name, so it was ignored' \
  "$(P --name laptop --ssh typo=x@y | jq -r '.warnings[] | select(startswith("--ssh"))')"
check "a --check-only for a linked machine leaves it linked, and is named" 'env-new --check-only new: a linked machine has that name, so it was not made check-only' \
  "$(P --name laptop --check-only new=gharib@new | jq -r '"\(.fleet.machines.new.environment_id) \(.warnings[] | select(startswith("--check-only")))"')"
check "a malformed --ssh is a usage error" 2 "$(P --name laptop --ssh new >/dev/null 2>&1; echo $?)"

# --- a check-only machine: an ssh string, no environment id, the marker -----------------------
reset
out=$(P --name laptop --check-only nas=admin@nas)
check "a check-only machine is accepted when its test passes" '{"ssh":"admin@nas","check_only":true,"environment_id":null}' \
  "$(jq -c '.fleet.machines.nas | {ssh, check_only, environment_id}' <<<"$out")"
S --name laptop --check-only nas=admin@nas --write >/dev/null
check "and a re-run keeps it" '{"ssh":"admin@nas","check_only":true}' "$(P --name laptop | jq -c '.fleet.machines.nas | {ssh, check_only}')"
rm -f "$fleet"
sa_ssh admin@nas 255 '' 'ssh: Could not resolve hostname nas: Name or service not known'
out=$(P --name laptop --check-only nas=admin@nas)
check "one whose test fails is refused, never added" "null nas" "$(jq -r '"\(.fleet.machines.nas) \(.ssh_refused[0].machine)"' <<<"$out")"
printf '%s\n' '{"machines":{"box":{"ssh":7}}}' > "$fleet"
check "a fleet file whose ssh is no string is refused" 2 "$(P --name laptop >/dev/null 2>&1; echo $?)"

finish
