#!/usr/bin/env bash
# super-agent's `schedules`, driven through its command line over a fleet file:
# the schedule proposal names a morning report and one weekly retro-run per active
# repo and creates nothing.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fleet=$tmp/fleet.json
S() { bash "$s/schedules.sh" --fleet "$fleet" "$@"; }

jq -n '{machines: {}, active_repos: ["acme/widgets", "acme/gears"]}' > "$fleet"

# --- the contract every script keeps ------------------------------------------
x=schedules
out=$(bash "$s/$x.sh" --help 2>"$tmp/err"); rc=$?
check "$x --help opens with its usage line" "usage: $x" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "$x --help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "$x --help exits 0" 0 "$rc"
out=$(bash "$s/$x.sh" --bogus 2>/dev/null); rc=$?
check "$x: a bad flag answers its usage line" "$(sed -n 1p <<<"$(bash "$s/$x.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "$x: a bad flag exits 2" 2 "$rc"
check_rc "schedules with a malformed time exits 2" 2 "$(S --morning 8am >/dev/null 2>&1; echo $?)"
check_rc "schedules with a time past 23:59 exits 2" 2 "$(S --morning 24:00 >/dev/null 2>&1; echo $?)"
check_rc "schedules with a day outside 0 to 6 exits 2" 2 "$(S --retro-day 7 >/dev/null 2>&1; echo $?)"

# --- the schedule proposal -------------------------------------------------------
out=$(S); rc=$?
check_rc "schedules exits 0" 0 "$rc"
check "a morning report in this thread on weekdays at 08:00" 'this-thread fixed_time 08:00 [1,2,3,4,5]' \
  "$(jq -r '.morning | "\(.bind) \(.schedule.type) \(.schedule.timeOfDay) \(.schedule.weekdays | tojson)"' <<<"$out")"
check "the morning prompt asks for the digest block" true "$(jq '.morning.prompt | contains("status.sh --digest")' <<<"$out")"
check "one retro-run per active repo" "acme/widgets acme/gears" "$(jq -r '[.retro[].repo] | join(" ")' <<<"$out")"
check "each weekly on Friday at 09:00 in the repo's project" 'repo-project 5 09:00 /retro-run' \
  "$(jq -r '.retro[0] | "\(.bind) \(.schedule.weekdays[0]) \(.schedule.timeOfDay) \(.prompt)"' <<<"$out")"
out=$(S --morning 07:30 --retro-day 1)
check "the time and day are flags" '07:30 1' "$(jq -r '"\(.morning.schedule.timeOfDay) \(.retro[0].schedule.weekdays[0])"' <<<"$out")"
# --- the work week comes from the fleet file ------------------------------------
jq '.work_week = [0,1,2,3,4]' "$fleet" > "$tmp/sun.json"
out=$(bash "$s/schedules.sh" --fleet "$tmp/sun.json")
check "a Sunday-to-Thursday fleet runs the morning report on those days" '[0,1,2,3,4]' "$(jq -c .morning.schedule.weekdays <<<"$out")"
check "and the retro defaults to its last day, Thursday" 4 "$(jq -r '.retro[0].schedule.weekdays[0]' <<<"$out")"
out=$(bash "$s/schedules.sh" --fleet "$tmp/sun.json" --retro-day 2)
check "an explicit --retro-day still wins" 2 "$(jq -r '.retro[0].schedule.weekdays[0]' <<<"$out")"
jq '.work_week = [3,1,2]' "$fleet" > "$tmp/mid.json"
check "the last day is the last of the week's order, not the largest number" 2 \
  "$(bash "$s/schedules.sh" --fleet "$tmp/mid.json" | jq -r '.retro[0].schedule.weekdays[0]')"
for bad in '[]' '"x"' 'false' '[7]' '[1,1]'; do
  jq --argjson w "$bad" '.work_week = $w' "$fleet" > "$tmp/bad.json"
check_rc "a work_week of $bad exits 2" 2 "$(bash "$s/schedules.sh" --fleet "$tmp/bad.json" >/dev/null 2>&1; echo $?)"
done
jq '.work_week = [6]' "$fleet" > "$tmp/sat.json"
out=$(bash "$s/schedules.sh" --fleet "$tmp/sat.json")
check "Saturday is accepted for morning and retro" '[[6],[6]]' "$(jq -c '[.morning.schedule.weekdays, .retro[0].schedule.weekdays]' <<<"$out")"

jq '.active_repos = []' "$fleet" > "$tmp/none.json"
check "no active repos proposes no retro-run" '[]' "$(bash "$s/schedules.sh" --fleet "$tmp/none.json" | jq -c .retro)"
check "the proposal holds no path" 0 "$(S | grep -c '/home/\|/tmp/')"


finish
