#!/usr/bin/env bash
# super-agent's `scorecard`, driven through its command line: a day's row counted
# from a hand-built ledger, archive, guard and timer logs and transcript; the
# transcript found by thread id; and the weekly review over a week of rows.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh
source tests/super-agent-launch-lib.sh

export HOME=$tmp/home CLAUDE_CONFIG_DIR='' T3CODE_THREAD_ID=''
sc=$s/scorecard.sh
day=2026-11-19
dir=$(dirname "$led")
card=$dir/scorecard.jsonl
R() { bash "$sc" row --ledger "$led" "$@"; }

# --- transcript fixture: one JSON line per entry, built by hand --------------
u() { jq -cn --arg ts "$1" --arg t "$2" '{type: "user", timestamp: $ts, message: {role: "user", content: $t}}'; }
result() { jq -cn --arg ts "$1" '{type: "user", timestamp: $ts, message: {role: "user", content: [{type: "tool_result", content: "ok"}]}}'; }
# a <ts> <message id> <usage json> <content json>
a() { jq -cn --arg ts "$1" --arg id "$2" --argjson us "$3" --argjson c "$4" \
  '{type: "assistant", timestamp: $ts, message: {id: $id, model: "claude-x", usage: $us, content: $c}}'; }
txt() { jq -cn --arg t "$1" '{type: "text", text: $t}'; }
bash_call() { jq -cn --arg c "$1" --arg id "${2:-x}" --argjson bg "${3:-false}" \
  '{type: "tool_use", name: "Bash", id: $id, input: {command: $c, run_in_background: $bg}}'; }
use() { jq -cn --argjson i "$1" --argjson cr "$2" --argjson o "$3" \
  '{input_tokens: $i, cache_creation_input_tokens: 0, cache_read_input_tokens: $cr, output_tokens: $o}'; }
long=$(printf "%01600d" 0)

transcript() { # the day's three wakes, a wake the day before, and noise that is no wake
  u "2026-11-18T23:50:00Z" "an owner message the day before?"
  a "2026-11-18T23:50:05Z" m0 "$(use 1 0 1)" "[$(txt "Yesterday.")]"
  u "${day}T10:00:00Z" "why is #7 still open?"
  a "${day}T10:00:05Z" m1 "$(use 10 100 5)" "[$(txt "Because it waits on review."), $(bash_call "gh issue close 7"),
    $(bash_call "bash skills/super-agent/scripts/watch.sh --ledger l" bg1 true)]"
  result "${day}T10:00:06Z"
  u "${day}T10:10:00Z" "<task-notification><tool-use-id>bg1</tool-use-id><status>completed</status></task-notification>"
  a "${day}T10:10:05Z" m2 "$(use 1 0 1)" "[$(txt "Nothing has changed.")]"
  u "${day}T10:20:00Z" "<system-reminder>boilerplate is no wake</system-reminder>"
  u "${day}T11:00:00Z" "Backstop: check the ledger"
  a "${day}T11:00:05Z" m3 "$(use 5 0 1)" "[$(txt "$long")]"
  a "${day}T11:00:06Z" m3 "$(use 5 0 3)" "[$(bash_call "bash ledger.sh --ledger l need acme/widgets#7 --action merge"),
    $(bash_call "bash ledger.sh --ledger l pushed 'acme/widgets#7'"), $(bash_call "bash ledger.sh --ledger l pushed acme/widgets#7")]"
  jq -cn --arg ts "${day}T11:30:00Z" '{type: "assistant", isSidechain: true, timestamp: $ts,
    message: {id: "side", model: "claude-x", usage: {input_tokens: 1000}, content: [{type: "text", text: "a subagent"}]}}'
  printf 'not json\n'
}

ledger_fixture() {
  rm -f "$led" "$led.archive.jsonl" "$card" "$dir"/*-guard.jsonl "$dir/wake-timer.jsonl"
  bash "$s/ledger.sh" --ledger "$led" add --repo "$repo" --number 7 --thread th-7 --worktree /wt/7 --branch b-7 >/dev/null
  bash "$s/ledger.sh" --ledger "$led" add --repo "$repo" --number 8 --thread th-8 --worktree /wt/8 --branch b-8 >/dev/null
  bash "$s/ledger.sh" --ledger "$led" add --repo "$repo" --number 10 --thread th-10 --worktree /wt/10 --branch b-10 >/dev/null
  jq '.entries["acme/widgets#7"].launched_at = "2026-11-18T09:00:00Z"
    | .entries["acme/widgets#8"] += {launched_at: "2026-11-19T08:00:00Z", stage: "settled", settled_at: "2026-11-19T12:00:00Z"}
    | .entries["acme/widgets#10"].launched_at = "2026-11-20T08:00:00Z"' "$led" > "$tmp/l" && mv "$tmp/l" "$led"
  jq -cn '{key: "acme/widgets#9", stage: "settled", launched_at: "2026-11-10T08:00:00Z", settled_at: "2026-11-12T08:00:00Z"}' \
    > "$led.archive.jsonl"
}

# --- the contract every script keeps ------------------------------------------
x=scorecard
out=$(bash "$sc" --help); rc=$?
check "$x --help opens with its usage line" "usage: $x" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "$x --help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "$x --help exits 0" 0 "$rc"
out=$(bash "$sc" row --ledger "$led" --bogus x 2>/dev/null); rc=$?
check "$x: a bad flag answers its usage line" "$(sed -n 1p <<<"$(bash "$sc" --help)")" "$(jq -r .error <<<"$out")"
check_rc "$x: a bad flag exits 2" 2 "$rc"
check "$x refuses a day that is no calendar day, exit 2" "2 2026-02-30: not a calendar day, YYYY-MM-DD" \
  "$(out=$(R --day 2026-02-30 --transcript /dev/null 2>/dev/null); echo "$? $(jq -r .error <<<"$out")")"

# --- one row from the hand-built fixture --------------------------------------
ledger_fixture
transcript > "$tmp/t.jsonl"
printf '%s\n' "{\"at\":\"${day}T09:00:00Z\",\"event\":\"block\"}" "{\"at\":\"${day}T09:05:00Z\",\"event\":\"pass\"}" \
  '{"at":"2026-11-18T09:00:00Z","event":"pass"}' > "$dir/watch-guard.jsonl"
printf '%s\n' "{\"at\":\"${day}T03:00:00Z\",\"event\":\"outage\",\"minutes\":5}" \
  "{\"at\":\"${day}T04:00:00Z\",\"event\":\"outage\",\"minutes\":20}" > "$dir/wake-timer.jsonl"
out=$(R --day "$day" --transcript "$tmp/t.jsonl" --version 9.9.9); rc=$?
check_rc "a row exits 0" 0 "$rc"
row=$(jq -c .row <<<"$out")
check "the row is appended to scorecard.jsonl beside the ledger" "$card $row" "$(jq -r .file <<<"$out") $(cat "$card")"
check "it is stamped with the day and the version" '2026-11-19 ["9.9.9"]' "$(jq -c '"\(.day) \(.versions)"' -r <<<"$row")"
check "workload: entries open at any point of the day, entries settled that day (archive read too)" \
  '{"open":2,"settled":1}' "$(jq -c .workload <<<"$row")"
check "messages: count, per open entry, nothing changed, over 1,500 characters, median length" \
  '{"count":3,"per_open":1.5,"nothing_changed":1,"over_1500":1,"median_chars":27}' "$(jq -c .messages <<<"$row")"
check "needs: recorded, alerted, alerted more than once" '{"recorded":1,"alerted":2,"alerted_twice":1}' "$(jq -c .needs <<<"$row")"
check "guards: the day's blocks and passes, by guard" '{"watch":{"blocks":1,"passes":1}}' "$(jq -c .guards <<<"$row")"
check "timer: the day's outages, median and worst minutes" '{"outages":2,"median_minutes":12.5,"worst_minutes":20}' "$(jq -c .timer <<<"$row")"
check "questions: owner questions, and those followed by a write in the same turn" '{"asked":1,"with_write":1}' "$(jq -c .questions <<<"$row")"
check "wakes: count, per open entry, by cause, and those that changed nothing" \
  '{"count":3,"per_open":1.5,"by_cause":{"backstop":1,"owner":1,"watcher":1},"changed_nothing":1}' "$(jq -c .wakes <<<"$row")"
check "tokens: once per API call, weighted, per open entry, and the no-change share" \
  '{"total":125,"weighted":71,"per_open":35.5,"nothing_changed_share":0.08}' "$(jq -c .tokens <<<"$row")"
R --day "$day" --transcript "$tmp/t.jsonl" --version 9.9.9 >/dev/null
R --day 2026-11-18 --transcript "$tmp/t.jsonl" --version 9.9.9 >/dev/null
check "a day counted again replaces its row; another day is appended" "2026-11-18 2026-11-19" \
  "$(jq -r .day "$card" | sort | tr '\n' ' ' | sed 's/ $//')"

# --- a log not written yet reads as absent -------------------------------------
rm -f "$dir/watch-guard.jsonl" "$dir/wake-timer.jsonl"
out=$(R --day "$day" --transcript "$tmp/t.jsonl" --version 9.9.9); rc=$?
check "no guard or timer log: exit 0, both absent, the rest still counted" "0 null null 3" \
  "$rc $(jq -c .row.guards <<<"$out") $(jq -c .row.timer <<<"$out") $(jq .row.messages.count <<<"$out")"

# --- the transcript, found by thread id ----------------------------------------
proj=$HOME/.claude/projects/p
mkdir -p "$proj/subagents"
loaded=$(u "${day}T09:00:00Z" "Base directory for this skill: /x/.claude/skills/super-agent")
pinned() { # <file> <thread id> <messages>
  { printf '%s\n' "$loaded"; u "${day}T09:01:00Z" "Handed over from thread $2."
    for ((i = 1; i <= $3; i++)); do a "${day}T09:0${i}:30Z" "m$2$i" "$(use 1 0 1)" "[$(txt "message $i")]"; done; } > "$1"
}
pinned "$proj/arg.jsonl" th-arg 1
pinned "$proj/led.jsonl" th-led 2
pinned "$proj/env.jsonl" th-env 3
{ u "${day}T09:00:00Z" "launched by th-arg"; u "${day}T09:00:01Z" "Base directory for this skill: /x/.claude/skills/ship-run"
  a "${day}T09:01:00Z" c1 "$(use 1 0 1)" "[$(txt "a child quoting Base directory for this skill: /x/super-agent")]"; } > "$proj/child.jsonl"
cp "$proj/arg.jsonl" "$proj/subagents/arg.jsonl"
count() { jq -r '"\(.row.messages.count) \(.row.thread)"' <<<"$1"; }
jq '.own_thread = "th-led"' "$led" > "$tmp/l" && mv "$tmp/l" "$led"
check "--thread wins, and only a transcript that loaded the skill counts (no child, no subagent)" "1 th-arg" \
  "$(count "$(T3CODE_THREAD_ID=th-env R --day "$day" --thread th-arg)")"
check "else the ledger's own_thread" "2 th-led" "$(count "$(T3CODE_THREAD_ID=th-env R --day "$day")")"
jq 'del(.own_thread)' "$led" > "$tmp/l" && mv "$tmp/l" "$led"
check "else the thread id in the environment" "3 th-env" "$(count "$(T3CODE_THREAD_ID=th-env R --day "$day")")"
out=$(R --day "$day" 2>/dev/null); rc=$?
check "no thread id at all is refused by name, exit 2" "2 no thread id: pass --thread, or run in the super agent's thread" \
  "$rc $(jq -r .error <<<"$out")"
check "the row is stamped with the running copy's version by default" \
  "$(sed -n 's/^  version: //p' "$s/../SKILL.md")" "$(R --day "$day" --thread th-arg | jq -r '.row.versions[0]')"

# --- the weekly review over a full week ----------------------------------------
cat > "$tmp/targets.json" <<'JSON'
{"needs.alerted_twice": {"max": 0}, "timer.worst_minutes": {"max": 15}}
JSON
rowfor() { # <day> <alerted twice> <worst minutes> <watch blocks or "">
  jq -cn --arg d "$1" --argjson n "$2" --argjson m "$3" --arg b "${4:-}" \
    '{day: $d, messages: {count: 500}, needs: {alerted_twice: $n}, timer: {worst_minutes: $m},
      guards: (if $b == "" then null else {watch: {blocks: ($b | tonumber), passes: 0}} end)}'
}
week() { # the week of 9 to 15 Nov, with the given alerted-twice count on its Wednesday
  for d in 09 10 11 12 13 14 15; do rowfor "2026-11-$d" "$([ "$d" = 11 ] && echo "$1" || echo 0)" 10 "${2:-}"; done
}
V() { SA_NOW=$(jq -n '"2026-11-18T08:00:00Z" | fromdateiso8601') bash "$sc" review --ledger "$led" --targets "$tmp/targets.json" "$@"; }
week 0 > "$card"
out=$(V); rc=$?
check "a week where every target holds prints nothing, and the default week is the last full one" \
  '0 {"from":"2026-11-09","to":"2026-11-15"} 7 []' "$rc $(jq -c .week <<<"$out") $(jq .days <<<"$out") $(jq -c .needs <<<"$out")"
week 2 > "$card"
check "a number that missed its target is one row naming it (a number with no target raises none)" \
  '["Scorecard: needs.alerted_twice missed its target of 0 on 1 of 7 days (worst 2)."]' "$(V | jq -c .needs)"
{ for d in 19 20 21 22 23 24 25 26 27 28 29 30; do rowfor "2026-10-$d" 0 10 0; done
  for d in 01 02 03 04 05 06 07 08; do rowfor "2026-11-$d" 0 10 0; done; week 0 0; } > "$card"
check "a guard with zero blocks for four weeks is one row" \
  '["Scorecard: the watch guard blocked nothing for four weeks; delete it?"]' "$(V | jq -c .needs)"
{ for d in 20 21 22 23 24 25 26 27 28 29 30; do rowfor "2026-10-$d" 0 10 0; done
  for d in 01 02 03 04 05 06 07 08; do rowfor "2026-11-$d" 0 10 0; done; week 0 0; } > "$card"
check "a guard logged for less than four weeks raises none" '[]' "$(V | jq -c .needs)"
{ for d in 19 20 21 22 23 24 25 26 27 28 29 30; do rowfor "2026-10-$d" 0 10 0; done
  rowfor 2026-11-01 0 10 1; for d in 02 03 04 05 06 07 08; do rowfor "2026-11-$d" 0 10 0; done; week 0 0; } > "$card"
check "a guard that blocked once in the four weeks raises none" '[]' "$(V | jq -c .needs)"
check "--week reviews the week given" '{"from":"2026-11-02","to":"2026-11-08"} 7' \
  "$(V --week 2026-11-02 | jq -r '"\(.week | tojson) \(.days)"')"

finish
