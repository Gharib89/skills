#!/usr/bin/env bash
# Every super-agent script that compares a repo name, a ledger key or an area
# path normalises both sides through _lib.sh: a mixed-case repo name and a path
# with a trailing slash or a leading `./` answer as the exact spelling does.
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
fleet=$tmp/fleet.json led=$tmp/ledger.json
printf '%s\n' '{"machines":{"home":{"slots":5},"box":{"slots":5}},"active_repos":["Acme/Widgets"]}' > "$fleet"
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
LC() { bash "$s/launch-check.sh" --fleet "$fleet" --ledger "$led" --own home --machine box --load 1 --free-gb 8 "$@"; }
L add --repo acme/widgets --number 5 --thread t5 --worktree /wt/5 --branch b5 --area skills/ship >/dev/null

# --- launch-check: repo name and area path ---------------------------------------
for spelling in "acme/widgets skills/ship" "ACME/Widgets skills/ship" "acme/widgets ./skills/ship/" "Acme/WIDGETS skills/ship//"; do
  set -- $spelling
  check "launch-check: $spelling conflicts with the open ticket" '["acme/widgets#5"]' "$(LC --repo "$1" --area "$2" | jq -c .repo.conflicts)"
done
check "launch-check: a mixed-case repo with an apart area is free" '[]' "$(LC --repo ACME/Widgets --area docs/ | jq -c .repo.conflicts)"
check "launch-check: --key in another case leaves the ticket's own entry out" '[]' "$(LC --repo acme/widgets --key ACME/Widgets#5 --area skills/ship | jq -c .repo.conflicts)"

# --- ledger: a key in another case names the same entry ----------------------------
check "ledger get: a mixed-case key finds the entry" acme/widgets#5 "$(L get ACME/Widgets#5 | jq -r .key)"
check_rc "ledger add: a mixed-case key is already in the ledger" 1 "$(L add --repo Acme/Widgets --number 5 --thread t --worktree /w --branch b >/dev/null 2>&1; echo $?)"
L set ACME/WIDGETS#5 stage '"running"' >/dev/null
check "ledger set: a mixed-case key writes the entry" running "$(L get acme/widgets#5 | jq -r .stage)"
L wait acme/widgets#6 --reason r >/dev/null; L wait ACME/Widgets#6 --reason r2 >/dev/null
check "ledger wait: a repeat in another case is one row" 1 "$(L list | jq '.waiting | length')"
check "ledger unwait: a mixed-case key removes it" true "$(L unwait ACME/WIDGETS#6 | jq .removed)"

# --- track: a mixed-case repo is the tracked one --------------------------------------
check "track: tracking it in another case changes nothing" false "$(bash "$s/track.sh" --fleet "$fleet" track ACME/widgets | jq .changed)"
check "track: stopping it in another case removes it" '[]' "$(bash "$s/track.sh" --fleet "$fleet" stop acme/WIDGETS | jq -c .active_repos)"

# --- intake: the ledger holds the ticket under another case -----------------------------
printf '%s\n' '{"machines":{"alpha":{}},"active_repos":["Acme/Widgets"]}' > "$fleet"
sa_route user '{"login":"octo"}'
sa_route "repos/Acme/Widgets/issues?state=open&labels=ready-for-agent&per_page=100" '[{"number":5,"title":"Five","labels":[{"name":"ready-for-agent"}]}]'
out=$(bash "$s/intake.sh" --fleet "$fleet" --ledger "$led" --machine alpha --thread th-a 2>/dev/null)
check "intake: a ticket the ledger holds under another case is held" '["Acme/Widgets#5"]' "$(jq -c .held <<<"$out")"

finish
