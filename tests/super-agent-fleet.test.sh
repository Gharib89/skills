#!/usr/bin/env bash
# super-agent's `fleet`, driven through its command line over a fleet file: `pin`
# fixes a repo to one machine and `unpin` frees it, `slots` sets a machine's slot
# count; each is idempotent, leaves every other key as it was, and refuses a
# machine the file lacks, a bad count or a bad file.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fleet=$tmp/fleet.json
F() { bash "$s/fleet.sh" --fleet "$fleet" "$@"; }
seed() { printf '%s\n' '{"machines":{"home":{"slots":3,"reserve":1},"box":{"slots":2,"environment_id":"e1"}},"waivers":[{"id":"w"}],"repos":{"acme/widgets":{"max_ships":2,"brief":["x"]}}}' > "$fleet"; }

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/fleet.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: fleet" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
seed
out=$(bash "$s/fleet.sh" --bogus 2>/dev/null); rc=$?
check "a bad flag answers the usage line" "$(sed -n 1p <<<"$(bash "$s/fleet.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad flag exits 2" 2 "$rc"
check_rc "an unknown action exits 2" 2 "$(F stop acme/widgets >/dev/null 2>&1; echo $?)"
check_rc "pin with no machine exits 2" 2 "$(F pin acme/widgets >/dev/null 2>&1; echo $?)"
check_rc "a repo that is no owner/name exits 2" 2 "$(F pin widgets box >/dev/null 2>&1; echo $?)"

# --- pin ---------------------------------------------------------------------------
out=$(F pin acme/gears box); rc=$?
check_rc "pin exits 0" 0 "$rc"
check "it answers the repo's machine" '{"action":"pin","repo":"acme/gears","machine":"box","changed":true}' "$(jq -c '{action, repo, machine, changed}' <<<"$out")"
check "the file holds it" '"box"' "$(jq -c '.repos["acme/gears"].machine' "$fleet")"
check "every other key is as it was" '{"machines":{"home":{"slots":3,"reserve":1},"box":{"slots":2,"environment_id":"e1"}},"waivers":[{"id":"w"}],"repos":{"acme/widgets":{"max_ships":2,"brief":["x"]}}}' "$(jq -c 'del(.repos["acme/gears"])' "$fleet")"
out=$(F pin acme/widgets home)
check "pinning a repo with other keys keeps them" '{"max_ships":2,"brief":["x"],"machine":"home"}' "$(jq -c '.repos["acme/widgets"]' "$fleet")"
check "pinning it again changes nothing" false "$(F pin acme/widgets home | jq .changed)"
check "a repo in another case is the same repo" 'false ["acme/gears","acme/widgets"]' "$(F pin Acme/Widgets home | jq -r .changed) $(jq -c '.repos | keys' "$fleet")"
check "and moving a pin changes it" '"box"' "$(F pin ACME/WIDGETS box >/dev/null; jq -c '.repos["acme/widgets"].machine' "$fleet")"
out=$(F pin acme/widgets nowhere 2>/dev/null); rc=$?
check "a machine the file lacks exits 2, naming it" "2 1" "$rc $(jq -r .error <<<"$out" | grep -c nowhere)"
check "and leaves the pin as it was" '"box"' "$(jq -c '.repos["acme/widgets"].machine' "$fleet")"

# --- unpin -------------------------------------------------------------------------
out=$(F unpin acme/widgets); rc=$?
check_rc "unpin exits 0" 0 "$rc"
check "it removes the pin and keeps the repo's other keys" 'true {"max_ships":2,"brief":["x"]}' "$(jq -r .changed <<<"$out") $(jq -c '.repos["acme/widgets"]' "$fleet")"
check "unpinning a free repo changes nothing" false "$(F unpin acme/widgets | jq .changed)"
F unpin acme/gears >/dev/null
check "a repo left with no key is dropped" false "$(jq 'has("repos") and (.repos | has("acme/gears"))' "$fleet")"

# --- slots -------------------------------------------------------------------------
out=$(F slots box 4); rc=$?
check_rc "slots exits 0" 0 "$rc"
check "it answers the machine's count" '{"action":"slots","machine":"box","slots":4,"changed":true}' "$(jq -c '{action, machine, slots, changed}' <<<"$out")"
check "the file holds it, the machine's other keys untouched" '{"slots":4,"environment_id":"e1"}' "$(jq -c .machines.box "$fleet")"
check "the same count changes nothing" false "$(F slots box 4 | jq .changed)"
for bad in 0 -1 1.5 two ''; do
  check_rc "a count of '$bad' exits 2" 2 "$(F slots box "$bad" >/dev/null 2>&1; echo $?)"
done
check_rc "a count that leaves no slot past the machine's reserve exits 2" 2 "$(F slots home 1 >/dev/null 2>&1; echo $?)"
check "and leaves the count as it was" 3 "$(jq .machines.home.slots "$fleet")"
check_rc "a machine the file lacks exits 2" 2 "$(F slots nowhere 2 >/dev/null 2>&1; echo $?)"

# --- a file the script refuses ---------------------------------------------------------
check_rc "a missing file exits 2" 2 "$(bash "$s/fleet.sh" --fleet "$tmp/none.json" slots box 2 >/dev/null 2>&1; echo $?)"
echo '[]' > "$fleet"
check_rc "a fleet that is not an object exits 2" 2 "$(F slots box 2 >/dev/null 2>&1; echo $?)"
seed; jq '.repos = []' "$fleet" > "$tmp/r.json"; cp "$tmp/r.json" "$fleet"
check_rc "repos that is not an object exits 2" 2 "$(F pin acme/w box >/dev/null 2>&1; echo $?)"

finish
