#!/usr/bin/env bash
# super-agent's `brief` and `schedules`, driven through their command lines over
# a fleet file and a ledger: the launch brief carries the fleet file's waivers
# word for word, the owner's allowed calls and the escalation rule; the schedule
# proposal names a morning report and one weekly retro-run per active repo and
# creates nothing.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fleet=$tmp/fleet.json led=$tmp/ledger.json
B() { bash "$s/brief.sh" --fleet "$fleet" --ledger "$led"; }
S() { bash "$s/schedules.sh" --fleet "$fleet" "$@"; }

# the fleet file setup proposes: the three standing waivers, as setup writes them
w1='Codex answers a review request with a usage-limit notice: drive the fallback reviewer and record Codex as not landed; do not hold the merge gate for it.'
w2='A live end-to-end proof needs a real T3 server or other machines: prove it through the scripts over fake CLIs and say so in the PR body.'
w3='The last fix after the review cap is reached may merge without another review round: record it in the PR body.'
jq -n --arg a "$w1" --arg b "$w2" --arg c "$w3" '{machines: {}, active_repos: ["acme/widgets", "acme/gears"],
  waivers: [{id: "codex-usage-limit", condition: $a}, {id: "offline-live-e2e", condition: $b}, {id: "last-fix-after-cap", condition: $c}]}' > "$fleet"

# --- the contract every script keeps ------------------------------------------
for x in brief schedules; do
  out=$(bash "$s/$x.sh" --help 2>"$tmp/err"); rc=$?
  check "$x --help opens with its usage line" "usage: $x" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
  check "$x --help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
  check_rc "$x --help exits 0" 0 "$rc"
  out=$(bash "$s/$x.sh" --bogus 2>/dev/null); rc=$?
  check "$x: a bad flag answers its usage line" "$(sed -n 1p <<<"$(bash "$s/$x.sh" --help)")" "$(jq -r .error <<<"$out")"
  check_rc "$x: a bad flag exits 2" 2 "$rc"
done
check_rc "brief with no ledger exits 2" 2 "$(bash "$s/brief.sh" --fleet "$fleet" >/dev/null 2>&1; echo $?)"
check_rc "brief with a missing fleet file exits 2" 2 "$(bash "$s/brief.sh" --fleet "$tmp/none.json" --ledger "$led" >/dev/null 2>&1; echo $?)"
check_rc "schedules with a malformed time exits 2" 2 "$(S --morning 8am >/dev/null 2>&1; echo $?)"
check_rc "schedules with a time past 23:59 exits 2" 2 "$(S --morning 24:00 >/dev/null 2>&1; echo $?)"
check_rc "schedules with a day outside 0 to 6 exits 2" 2 "$(S --retro-day 7 >/dev/null 2>&1; echo $?)"

# --- the brief lists the three waivers with their conditions -------------------
out=$(B); rc=$?
check_rc "brief exits 0" 0 "$rc"
brief=$(jq -r .brief <<<"$out")
check "it counts three waivers" 3 "$(jq .waivers <<<"$out")"
check "waiver 1 verbatim, numbered" "  1. $w1" "$(grep -F "$w1" <<<"$brief")"
check "waiver 2 verbatim, numbered" "  2. $w2" "$(grep -F "$w2" <<<"$brief")"
check "waiver 3 verbatim, numbered" "  3. $w3" "$(grep -F "$w3" <<<"$brief")"
check "the merge allowance is stated" 1 "$(grep -c '^Merge allowance: merge when /ship.s merge gate is clean, nothing wider' <<<"$brief")"
check "a hold outside them stops at the gate and is escalated" 1 "$(grep -c '^Any hold outside the merge allowance and these waivers stops at the gate' <<<"$brief")"
check "harmless commands need no hold" 1 "$(grep -c '^Commands harmless to run' <<<"$brief")"
check "the branch rule is there" 1 "$(grep -c '^Work in the worktree you start in, on the branch it holds' <<<"$brief")"
wl='Waiting on my own background work.'
check "the waiting line is there, word for word, for a turn that only waits on its own background work" 1 "$(grep -cF "ends with this line, word for word, as its last line: \`$wl\`" <<<"$brief")"
check "and the final message is still the PR URL and gate state, never that line" 1 "$(grep -c 'never this line' <<<"$brief")"
check "and the closing line" "End your last message with the PR URL and the gate state." "$(tail -1 <<<"$brief")"
check "with no ruling there is no allowed-calls block" 0 "$(grep -c 'Calls the owner allowed' <<<"$brief")"

# --- the owner's rulings ride along ---------------------------------------------
bash "$s/ledger.sh" --ledger "$led" ruling "deny nothing" --allow "git push to the branch" >/dev/null
out=$(B); brief=$(jq -r .brief <<<"$out")
check "an allowed call is counted" 1 "$(jq .allowed <<<"$out")"
check "and listed under its heading" 1 "$(grep -c '^Calls the owner allowed, no hold needed:' <<<"$brief")"
check "with its line" 1 "$(grep -c 'git push to the branch' <<<"$brief")"

# --- a brief-bound ruling is carried word for word, one without the flag is not ------
check "with no brief-bound ruling there is no rulings block" '0 0' "$(jq -r '"\(.rulings) \(.brief | split("\n") | map(select(startswith("Owner rulings:"))) | length)"' <<<"$(B)")"
bash "$s/ledger.sh" --ledger "$led" ruling "Reviews are Claude self-review only: the hosted review action and Codex will not work." --brief >/dev/null
bash "$s/ledger.sh" --ledger "$led" ruling "a private note that stays out" >/dev/null
out=$(B); brief=$(jq -r .brief <<<"$out")
check "a --brief ruling appears verbatim" 1 "$(grep -cF 'Reviews are Claude self-review only: the hosted review action and Codex will not work.' <<<"$brief")"
check "one without the flag does not" 0 "$(grep -c 'a private note' <<<"$brief")"
check "they are counted" 1 "$(jq .rulings <<<"$out")"
check "under the Owner rulings heading, before the worktree line" 'Owner rulings: Work' \
  "$(grep -A99 '^Owner rulings:' <<<"$brief" | awk 'NR==1 {a=$1" "$2} /^Work in the worktree/ {print a" "$1; exit}')"
check "the launch brief still ends on its closing line" "End your last message with the PR URL and the gate state." "$(tail -1 <<<"$brief")"

# --- a fleet file with no waivers says so --------------------------------------
jq '.waivers = []' "$fleet" > "$tmp/none.json"
out=$(bash "$s/brief.sh" --fleet "$tmp/none.json" --ledger "$led")
check "no waivers is stated, not left blank" 1 "$(jq -r .brief <<<"$out" | grep -c '(none)')"
printf '{"waivers":{}}\n' > "$tmp/bad.json"
check_rc "a fleet file whose waivers are no array exits 2" 2 "$(bash "$s/brief.sh" --fleet "$tmp/bad.json" --ledger "$led" >/dev/null 2>&1; echo $?)"

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


# --- a launch's own brief: the rulings and fleet lines that match its repo and machine ------
led2=$tmp/ledger2.json
bash "$s/ledger.sh" --ledger "$led2" ruling "Everywhere ruling." --brief >/dev/null
bash "$s/ledger.sh" --ledger "$led2" ruling "Widgets-only ruling." --brief --repo Acme/Widgets >/dev/null
bash "$s/ledger.sh" --ledger "$led2" ruling "Gears-only ruling." --brief --repo acme/gears >/dev/null
bash "$s/ledger.sh" --ledger "$led2" ruling "Box-only ruling." --brief --machine box >/dev/null
bash "$s/ledger.sh" --ledger "$led2" ruling "Widgets on box ruling." --brief --repo acme/widgets --machine box >/dev/null
check_rc "a repo scope without --brief exits 2" 2 "$(bash "$s/ledger.sh" --ledger "$led2" ruling "x" --repo acme/widgets >/dev/null 2>&1; echo $?)"
check "the ledger keeps a ruling's scope" '{"repo":"Acme/Widgets","machine":null}' "$(bash "$s/ledger.sh" --ledger "$led2" briefed | jq -c '.briefed[1] | {repo, machine}')"
jq '.repos = {"acme/widgets": {"brief": ["Widgets fleet line."]}, "acme/gears": {"brief": ["Gears fleet line."]}} | .machines = {"home": {"brief": ["Home fleet line."]}, "box": {"brief": ["Box fleet line."]}}' "$fleet" > "$tmp/lines.json"
B2() { bash "$s/brief.sh" --fleet "$tmp/lines.json" --ledger "$led2" "$@"; }
b=$(B2 | jq -r .brief)
check "with no repo or machine only the unscoped ruling rides along, and no fleet line" '1 0' "$(grep -c 'Everywhere ruling' <<<"$b") $(grep -c 'fleet line' <<<"$b")"
out=$(B2 --repo acme/widgets --machine home); b=$(jq -r .brief <<<"$out")
check "for widgets on home: the unscoped and the widgets ruling, not the others" 'Everywhere ruling.|Widgets-only ruling.' \
  "$(grep -oE 'Everywhere ruling\.|Widgets-only ruling\.|Gears-only ruling\.|Box-only ruling\.|Widgets on box ruling\.' <<<"$b" | paste -sd'|')"
check "and the widgets and home fleet lines, repo first" 'Widgets fleet line.|Home fleet line.' "$(grep -oE '(Widgets|Home|Gears|Box) fleet line\.' <<<"$b" | paste -sd'|')"
check "the counts say so" '{"rulings":2,"lines":2}' "$(jq -c '{rulings, lines}' <<<"$out")"
b=$(B2 --repo ACME/Widgets --machine box | jq -r .brief)
check "for widgets on box: the repo-and-machine ruling joins, matched without case" 'Everywhere ruling.|Widgets-only ruling.|Box-only ruling.|Widgets on box ruling.' \
  "$(grep -oE 'Everywhere ruling\.|Widgets-only ruling\.|Gears-only ruling\.|Box-only ruling\.|Widgets on box ruling\.' <<<"$b" | paste -sd'|')"
b=$(B2 --repo acme/widgets --machine home --note "Check the migration first." | jq -r .brief)
check "a one-ticket note rides along under its heading" 'Note for this ticket: Check the migration first.' "$(grep -A1 '^Note for this ticket:' <<<"$b" | paste -sd' ' | sed 's/  */ /g')"
check "without a note there is no heading" 0 "$(B2 --repo acme/widgets | jq -r .brief | grep -c 'Note for this ticket')"
check "every brief carries the shared-machine lines: own PIDs only, a per-repo lock and a memory cap" '1 1 1 1' \
  "$(grep -c 'by their PID' <<<"$b") $(grep -c 'never `pkill`' <<<"$b") $(grep -c 'flock /tmp/super-agent-acme-widgets.lock' <<<"$b") $(grep -c 'MemoryMax' <<<"$b")"
check "two casings of one repo name one lock" "1 1" "$(B2 --repo Acme/Widgets | jq -r .brief | grep -c 'flock /tmp/super-agent-acme-widgets.lock') $(B2 --repo acme/widgets | jq -r .brief | grep -c 'flock /tmp/super-agent-acme-widgets.lock')"
check "the closing line is still last" "End your last message with the PR URL and the gate state." "$(tail -1 <<<"$b")"

# --- a wrong-shaped fleet brief is refused, never dropped ---------------------------
jq '.repos = {"acme/widgets": {"brief": "one line"}}' "$fleet" > "$tmp/bad1.json"
jq '.machines = {"home": {"brief": [1]}}' "$fleet" > "$tmp/bad2.json"
jq '.repos = ["acme/widgets"]' "$fleet" > "$tmp/bad3.json"
for f in bad1 bad2 bad3; do
  out=$(bash "$s/brief.sh" --fleet "$tmp/$f.json" --ledger "$led2" --repo acme/widgets --machine home); rc=$?
  check "a $f fleet exits 2 with a named error" "2 1" "$rc $(jq -r .error <<<"$out" | grep -c 'array of text lines')"
done

finish
