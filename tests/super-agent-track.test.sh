#!/usr/bin/env bash
# super-agent's `track`, driven through its command line over a fleet file:
# tracking adds a repo to the active repos, stopping removes it, both are
# idempotent, nothing else in the file moves, and a bad file or repo is refused.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fleet=$tmp/fleet.json
T() { bash "$s/track.sh" --fleet "$fleet" "$@"; }
seed() { printf '%s\n' '{"machines":{"home":{"slots":2}},"waivers":[{"id":"w"}],"owner_note":"kept","active_repos":["acme/widgets"]}' > "$fleet"; }

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/track.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: track" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
seed
out=$(bash "$s/track.sh" --bogus 2>/dev/null); rc=$?
check "a bad flag answers the usage line" "$(sed -n 1p <<<"$(bash "$s/track.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad flag exits 2" 2 "$rc"
check_rc "an unknown action exits 2" 2 "$(T watch acme/widgets >/dev/null 2>&1; echo $?)"
check_rc "a repo that is no owner/name exits 2" 2 "$(T track widgets >/dev/null 2>&1; echo $?)"
check_rc "a repo with a space exits 2" 2 "$(T track 'acme/wid gets' >/dev/null 2>&1; echo $?)"

# --- track adds ---------------------------------------------------------------
out=$(T track acme/gadgets); rc=$?
check_rc "track exits 0" 0 "$rc"
check "it answers the new list in the order tracked" '{"action":"track","repo":"acme/gadgets","changed":true,"active_repos":["acme/widgets","acme/gadgets"]}' \
  "$(jq -c '{action, repo, changed, active_repos}' <<<"$out")"
check "the file holds it" '["acme/widgets","acme/gadgets"]' "$(jq -c .active_repos "$fleet")"
check "and every other key is as it was" '{"machines":{"home":{"slots":2}},"waivers":[{"id":"w"}],"owner_note":"kept"}' \
  "$(jq -c 'del(.active_repos)' "$fleet")"
out=$(T track acme/gadgets)
check "tracking a tracked repo changes nothing" '{"changed":false,"n":2}' "$(jq -c '{changed, n: (.active_repos | length)}' <<<"$out")"

# --- stop removes -------------------------------------------------------------
out=$(T stop acme/widgets); rc=$?
check_rc "stop exits 0" 0 "$rc"
check "it answers the list without it" '{"changed":true,"active_repos":["acme/gadgets"]}' "$(jq -c '{changed, active_repos}' <<<"$out")"
check "the file holds it" '["acme/gadgets"]' "$(jq -c .active_repos "$fleet")"
out=$(T stop acme/widgets)
check "stopping an untracked repo changes nothing" '{"changed":false,"active_repos":["acme/gadgets"]}' "$(jq -c '{changed, active_repos}' <<<"$out")"
T stop acme/gadgets >/dev/null
check "stopping the last repo leaves an empty list" '[]' "$(jq -c .active_repos "$fleet")"

# --- GitHub names are case-insensitive ------------------------------------------
seed
check "tracking a repo in another case adds nothing" '{"changed":false,"active_repos":["acme/widgets"]}' "$(T track Acme/Widgets | jq -c '{changed, active_repos}')"
check "stopping it in another case removes it" '[]' "$(T stop ACME/WIDGETS | jq -c .active_repos)"

# --- a fleet file with no active_repos key yet --------------------------------
printf '%s\n' '{"machines":{}}' > "$fleet"
check "a file without the key gains it" '["acme/widgets"]' "$(T track acme/widgets | jq -c .active_repos)"

# --- a file the script refuses ------------------------------------------------
rm -f "$fleet"
out=$(T track acme/widgets 2>/dev/null); rc=$?
check_rc "a missing file exits 2" 2 "$rc"
check "and nothing is created" no "$([ -f "$fleet" ] && echo yes || echo no)"
echo 'nope' > "$fleet"
check_rc "a file that is not JSON exits 2" 2 "$(T track acme/widgets >/dev/null 2>&1; echo $?)"
echo '{"active_repos":"acme/widgets"}' > "$fleet"
check_rc "active_repos of the wrong shape exits 2" 2 "$(T track acme/widgets >/dev/null 2>&1; echo $?)"
check "and is left alone" '{"active_repos":"acme/widgets"}' "$(jq -c . "$fleet")"

finish
