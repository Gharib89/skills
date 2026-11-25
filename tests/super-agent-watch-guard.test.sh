#!/usr/bin/env bash
# super-agent's watch guard: `watch --owed` answers, read-only, whether a watcher
# is owed (owed `watcher`, `reconcile` first, or `none`), and the Stop hook
# `watch-guard` asks it: a stop with a watcher owed is blocked once, the second
# stop (the hook input says a stop hook is already active) passes, and every
# block, pass and stop it could not judge leaves a line in the state directory.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'kill "${live:-}" 2>/dev/null; rm -rf "$tmp"' EXIT
led=$tmp/ledger.json fleet=$tmp/fleet.json log=$tmp/watch-guard.jsonl
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
O() { bash "$s/watch.sh" --ledger "$led" --owed; }
H() { bash "$s/watch-guard.sh" --ledger "$led" --fleet "$fleet" <<<"$1"; }
stop='{"hook_event_name":"Stop","stop_hook_active":false}'
again='{"hook_event_name":"Stop","stop_hook_active":true}'
add() { L add --repo Gharib89/skills --number "$1" --thread "t-$1" --worktree "/wt/$1" --branch "feat/x-$1" >/dev/null; }
observe() { L set "Gharib89/skills#$1" observed '{"status":"running","run_count":1,"pending":0,"pr":{"number":null,"state":"none"}}' >/dev/null; }
snapshot() { (cd "$tmp" && find . -type f -print0 | sort -z | xargs -0 cksum; ls -a) 2>&1; }

# --- --owed: three ledger and lock states, and it writes nothing ----------------
out=$(bash "$s/watch.sh" --help)
check "--help names --owed, in its usage and its stdout fields" 2 "$(grep -c -- '--owed' <<<"$out")"
out=$(O); rc=$?
check "an empty ledger owes nothing" '{"owed":"none","open":0}' "$out"
check_rc "and exits 0" 0 "$rc"
add 5
check "an open entry with no observed state owes reconcile first" '{"owed":"reconcile","open":1}' "$(O)"
observe 5
check "an open, observed entry and no watcher owes the watcher" '{"owed":"watcher","open":1}' "$(O)"
before=$(snapshot)
O >/dev/null
check "asking writes nothing, no lock included" "$before" "$(snapshot)"
# a live watcher: a process whose command line is a watch.sh, holding the lock
(exec -a watch.sh /usr/bin/sleep 60) & live=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do args=$(/bin/ps -p "$live" -o args= 2>/dev/null); [[ $args == *watch.sh* ]] && break; /usr/bin/sleep 0.1; done
echo "$live" > "$led.watch"
check "a live watcher on the lock owes nothing" '{"owed":"none","open":1}' "$(O)"
echo 999999 > "$led.watch"
check "a lock whose pid is gone owes the watcher" '{"owed":"watcher","open":1}' "$(O)"
rm -f "$led.watch"
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null
echo > "$led.watch"
check "a lock that reads empty owes nothing (a watcher mid-start)" '{"owed":"none","open":1}' "$(O)"
rm -f "$led.watch"
add 6
check "an observed entry beside an unobserved one still owes the watcher" '{"owed":"watcher","open":2}' "$(O)"
bash "$s/ledger.sh" --ledger "$led" drop 'Gharib89/skills#5' >/dev/null
bash "$s/ledger.sh" --ledger "$led" drop 'Gharib89/skills#6' >/dev/null
add 7; observe 7
sed -i 's/"stage": "launched"/"stage": "settled"/' "$led"
check "a settled entry owes nothing" '{"owed":"none","open":0}' "$(O)"

# --- the hook: blocked once, the second stop passes and is logged ----------------
rm -f "$led" "$log"; add 5; observe 5
out=$(H "$stop"); rc=$?
check_rc "a stop with a watcher owed exits 0 with a block decision" 0 "$rc"
check "and the decision is block" block "$(jq -r .decision <<<"$out")"
msg=$(jq -r .reason <<<"$out")
check "the message names the count of open entries" 1 "$(grep -c '1 open' <<<"$msg")"
check "and the watcher command with this ledger's and fleet's paths" 1 \
  "$(grep -cF "watch.sh' --ledger '$led' --fleet '$fleet' --timeout 7000" <<<"$msg")"
check "and says to end the turn" 1 "$(grep -c 'end the turn' <<<"$msg")"
out=$(H "$again"); rc=$?
check "the second stop passes, with no output" "0 " "$rc $out"
check "the log holds a block then a pass, each a JSON line with a time and an event" "block pass" \
  "$(jq -r 'select((.at | type) == "string") | .event' "$log" | tr '\n' ' ' | sed 's/ $//')"
check "a stop with a live watcher passes silently and logs nothing" "0 0" "$(
  (exec -a watch.sh /usr/bin/sleep 60) & w=$!; sleep 0.3; echo "$w" > "$led.watch"
  n=$(wc -l < "$log"); o=$(H "$stop"); r=$?; kill "$w"; wait "$w" 2>/dev/null; rm -f "$led.watch"
  echo "$r $(( $(wc -l < "$log") - n ))$o")"

# --- reconcile first names reconcile, then the watcher ---------------------------
rm -f "$led" "$log"; add 5; add 6
msg=$(jq -r .reason <<<"$(H "$stop")")
check "reconcile first: the count of open entries" 1 "$(grep -c '2 open' <<<"$msg")"
check "and the reconcile command with this ledger's and fleet's paths" 1 \
  "$(grep -cF "reconcile.sh' --ledger '$led' --fleet '$fleet'" <<<"$msg")"
check "then the watcher to start after it" 1 "$(grep -c 'watch.sh' <<<"$msg")"

# --- a hook that cannot judge allows the stop and leaves a log line ---------------
rm -f "$log"; printf 'not json' > "$led"
out=$(H "$stop"); rc=$?
check "an unreadable ledger allows the stop" "0 " "$rc $out"
check "and logs one unjudged line naming why" "unjudged 1" \
  "$(jq -r '[.event] | @tsv' "$log" | head -1) $(jq -r 'select(.why != null)' "$log" | jq -s length)"
rm -f "$log" "$led"; add 5; observe 5
out=$(H 'not json'); rc=$?
check "an unreadable hook input allows the stop" "0 " "$rc $out"
mkdir -p "$tmp/nojq"
for t in bash date dirname cat mkdir; do ln -s "$(command -v $t)" "$tmp/nojq/$t"; done
rm -f "$log"
out=$(PATH=$tmp/nojq bash "$s/watch-guard.sh" --ledger "$led" --fleet "$fleet" <<<"$stop"); rc=$?
check "a missing jq allows the stop" "0 " "$rc $out"
check "and leaves a log line, written without jq" unjudged "$(grep -o '"event":"unjudged"' "$log" | head -1 | cut -d'"' -f4)"
check "that line is JSON with a time" true "$(jq -s 'all(.[]; (.at | type) == "string")' "$log")"
rm -f "$log"
out=$(bash "$s/watch-guard.sh" --ledger "$tmp/missing-dir/x/ledger.json" --fleet "$fleet" <<<"$stop"); rc=$?
check "a ledger that does not exist is nothing owed, not a fault" "0 " "$rc $out"
check "and writes no log line" none "$([ -f "$log" ] && echo present || echo none)"
for partial in '{}' '{"stop_hook_active":"false"}'; do
  rm -f "$log"; out=$(H "$partial"); rc=$?
  check "a hook input with no boolean stop_hook_active ($partial) allows the stop, logged unjudged" "0  1" "$rc $out $(grep -c unjudged "$log")"
done
check "the generated Stop entry swallows a usage error's exit 2" 1 \
  "$(bash -c 'source "$1/_lib.sh"; sa_watch_guard_entry' _ "$PWD/$s" | jq -r '.hooks[0].command' | grep -c ' || true$')"
rm -f "$log"
out=$(H ""); rc=$?
check "an empty hook input allows the stop" "0 " "$rc $out"
check "and is logged as unjudged, not judged not-active" 1 "$(grep -c unjudged "$log")"

# --- the scorecard counts them: the target for unwatched passes is live (no slice tag) ---
check "the scorecard's target for unwatched passes is live, at 0" '{"max":0}' \
  "$(jq -c '."guards.watch.passes"' skills/super-agent/scorecard/targets.json)"

finish
