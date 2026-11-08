#!/usr/bin/env bash
# super-agent's `ledger`, driven through its command line: one JSON object per
# call, writes that are a temp file then a rename, and a ledger a fresh process
# reads back whole after a simulated restart.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
led=$tmp/state/ledger.json
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
add() { # <number> <thread>
  L add --repo Gharib89/skills --number "$1" --thread "$2" --worktree "/wt/$1" \
    --branch "feat/x-$1" --machine here --model claude-sonnet-5-5 --effort high
}

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/ledger.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: ledger" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/ledger.sh" 2>/dev/null); rc=$?
check "a bare call answers its usage line" "$(sed -n 1p <<<"$(bash "$s/ledger.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bare call exits 2" 2 "$rc"

# --- add: the ledger is created, one entry per ticket --------------------------
out=$(add 5 t-5); rc=$?
check_rc "add exits 0" 0 "$rc"
check "add names the entry's key" "Gharib89/skills#5" "$(jq -r .key <<<"$out")"
check "a new entry starts launched with no stalls and no observed state" \
  '{"stage":"launched","stalls":0,"observed":null}' "$(jq -c '.entry | {stage, stalls, observed}' <<<"$out")"
check "the entry holds the launch facts" \
  '{"repo":"Gharib89/skills","number":5,"thread":"t-5","worktree":"/wt/5","branch":"feat/x-5","machine":"here","model":"claude-sonnet-5-5","effort":"high"}' \
  "$(jq -c '.entry | {repo, number, thread, worktree, branch, machine, model, effort}' <<<"$out")"
check "the ledger file is there, in a directory add had to create" "Gharib89/skills#5" "$(jq -r '.entries | keys[]' "$led")"
out=$(add 5 t-5b 2>/dev/null); rc=$?
check_rc "a second add of the same ticket exits 1" 1 "$rc"
check "and says so" "Gharib89/skills#5 is already in the ledger" "$(jq -r .error <<<"$out")"
check "the refused add left the thread alone" t-5 "$(L get Gharib89/skills#5 | jq -r .thread)"

# --- a simulated restart: fresh processes read back every entry ---------------
add 6 t-6 >/dev/null; add 7 t-7 >/dev/null
L ruling "waive a Codex usage limit" >/dev/null
out=$(L list)
check "list reads back every entry after the writes of other processes" \
  "Gharib89/skills#5 Gharib89/skills#6 Gharib89/skills#7" "$(jq -r '[.entries[].key] | join(" ")' <<<"$out")"
check "and its rulings" "waive a Codex usage limit" "$(jq -r '.rulings[0].text' <<<"$out")"
check "each ruling is dated" 1 "$(jq '.rulings[0].date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | if . then 1 else 0 end' <<<"$out")"
check "get answers one entry" t-6 "$(L get Gharib89/skills#6 | jq -r .thread)"
out=$(L get Gharib89/skills#99 2>/dev/null); rc=$?
check_rc "get of a key the ledger lacks exits 1" 1 "$rc"
check "and names it" "Gharib89/skills#99 is not in the ledger" "$(jq -r .error <<<"$out")"

# --- rulings that allow a call: the launch brief carries them up front ----------
out=$(L allowed)
check "with no allowing ruling, no call is allowed" "[]" "$(jq -c .allowed <<<"$out")"
out=$(L ruling "approve the held pnpm install" --allow "pnpm install" --allow "pnpm run build")
day=$(jq -r .ruling.date <<<"$out")
check "a ruling records the calls it allows" '["pnpm install","pnpm run build"]' "$(jq -c .ruling.allow <<<"$out")"
check "a ruling with no --allow is dated and allows nothing" "waive a Codex usage limit [] 1" \
  "$(jq -r '.rulings[0] | "\(.text) \(.allow) \(.date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | if . then 1 else 0 end)"' <<<"$(L list)")"
out=$(L allowed)
check "allowed lists each call with its date" "pnpm install pnpm run build" "$(jq -r '[.allowed[].call] | join(" ")' <<<"$out")"
check "dated by its ruling" "$day" "$(jq -r '.allowed[0].date' <<<"$out")"
check "and written as the line the launch brief carries" \
  "Run \`pnpm install\` without a hold: the owner allowed it on $day." "$(jq -r '.allowed[0].line' <<<"$out")"

# --- a brief-bound ruling is marked, and `briefed` lists only those ---------------
out=$(L ruling "reviews are Claude self-review only" --brief)
check "a ruling added with --brief is marked brief-bound" true "$(jq .ruling.brief <<<"$out")"
check "one added without it is not" false "$(L ruling "plain" | jq .ruling.brief)"
out=$(L briefed)
check "briefed lists the brief-bound rulings with their date and text, word for word" "reviews are Claude self-review only" "$(jq -r '.briefed[].text' <<<"$out")"
check "and only those" 1 "$(jq '.briefed | length' <<<"$out")"
check "--brief composes with --allow" 'a call true' "$(L ruling both --allow "a call" --brief | jq -r '"\(.ruling.allow[0]) \(.ruling.brief)"')"
out=$(L ruling "x" --allow 2>/dev/null); rc=$?
check_rc "--allow with no call exits 2" 2 "$rc"

# --- set: one field, the stage a closed list ------------------------------------
out=$(L set Gharib89/skills#6 stage '"running"'); rc=$?
check_rc "set stage exits 0" 0 "$rc"
check "set answers the key, field and value" '{"key":"Gharib89/skills#6","field":"stage","value":"running"}' \
  "$(jq -c '{key, field, value}' <<<"$out")"
check "the change is in the file" running "$(jq -r '.entries["Gharib89/skills#6"].stage' "$led")"
out=$(L set Gharib89/skills#6 stage '"asleep"' 2>/dev/null); rc=$?
check_rc "a stage outside the list exits 1" 1 "$rc"
check "and names the list" "stage must be one of launched, running, at-rest, merged, settled, closed" "$(jq -r .error <<<"$out")"
check "the refused stage left the entry alone" running "$(jq -r '.entries["Gharib89/skills#6"].stage' "$led")"
L set Gharib89/skills#5 stage '"settled"' >/dev/null
check "list --open leaves settled entries out" "Gharib89/skills#6 Gharib89/skills#7" \
  "$(L list --open | jq -r '[.entries[].key] | join(" ")')"
L set Gharib89/skills#6 model null >/dev/null; rc=$?
check_rc "a JSON null is a value set accepts" 0 "$rc"
check "and it is stored" null "$(jq -c '.entries["Gharib89/skills#6"].model' "$led")"
L set Gharib89/skills#6 model false >/dev/null; rc=$?
check_rc "so is false" 0 "$rc"
out=$(L set Gharib89/skills#6 stalls 'not json' 2>/dev/null); rc=$?
check_rc "a value that is not JSON exits 2" 2 "$rc"
out=$(L set Gharib89/skills#6 repo '"x/y"' 2>/dev/null); rc=$?
check_rc "an entry's identity is not settable" 1 "$rc"
out=$(L set Gharib89/skills#99 stage '"running"' 2>/dev/null); rc=$?
check_rc "set on a key the ledger lacks exits 1" 1 "$rc"

# --- atomic writes: a temp file beside the ledger, then a rename ----------------
mkdir -p "$tmp/spy"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/mv-calls"\nexec /bin/mv "$@"\n' "$tmp" > "$tmp/spy/mv"
chmod +x "$tmp/spy/mv"
PATH="$tmp/spy:$PATH" add 8 t-8 >/dev/null
read -r from to < <(tail -1 "$tmp/mv-calls")
check "a write renames a temp file onto the ledger" "$led" "$to"
check "the temp file sits beside the ledger, so the rename is atomic" "$(dirname "$led")" "$(dirname "$from")"
check "and none is left behind" "ledger.json" "$(ls "$(dirname "$led")")"
before=$(cat "$led")
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/spy/mv"
out=$(PATH="$tmp/spy:$PATH" add 9 t-9 2>/dev/null); rc=$?
check_rc "a write whose rename fails exits 2" 2 "$rc"
check "and leaves the ledger as it was" "$before" "$(cat "$led")"
check "with no temp file left behind" "ledger.json" "$(ls "$(dirname "$led")")"

# --- a ledger of the wrong shape is refused by name -----------------------------
bad=$tmp/bad.json
printf '{"entries":[],"rulings":[]}\n' > "$bad"
out=$(bash "$s/ledger.sh" --ledger "$bad" list 2>/dev/null); rc=$?
check_rc "a ledger whose entries are not an object exits 2" 2 "$rc"
check "and names the file and the field" "$bad: entries must be an object" "$(jq -r .error <<<"$out")"
printf 'not json' > "$bad"
bash "$s/ledger.sh" --ledger "$bad" list >/dev/null 2>&1; rc=$?
check_rc "a ledger that is not JSON exits 2" 2 "$rc"

# --- the ledger is named, never guessed -----------------------------------------
out=$(bash "$s/ledger.sh" list 2>/dev/null); rc=$?
check_rc "a call without --ledger exits 2" 2 "$rc"
check "and answers the usage line" "$(sed -n 1p <<<"$(bash "$s/ledger.sh" --help)")" "$(jq -r .error <<<"$out")"
out=$(bash "$s/ledger.sh" --ledger "$tmp/none/ledger.json" list)
check "a ledger not yet written reads as empty" '{"entries":[],"rulings":[]}' "$(jq -c '{entries, rulings}' <<<"$out")"
check "and reading creates nothing" "" "$(ls "$tmp/none" 2>/dev/null)"

LR() { bash "$s/ledger.sh" --ledger "$tmp/re.json" "$@"; }
# --- rethread: a fresh thread for a ticket, its tracking started over -----------
LR add --repo Gharib89/skills --number 8 --thread t-8 --worktree /wt/8 --branch feat/x-8 >/dev/null
LR set Gharib89/skills#8 stalls 3 >/dev/null
LR set Gharib89/skills#8 rest_since '"2026-11-06T01:00:00Z"' >/dev/null
LR set Gharib89/skills#8 judged_run 4 >/dev/null
LR set Gharib89/skills#8 observed '{"status":"idle"}' >/dev/null
out=$(LR rethread Gharib89/skills#8 --thread t-9 --worktree /wt/9 --branch feat/x-9 --model sonnet --effort high)
check "rethread answers the entry" t-9 "$(jq -r .entry.thread <<<"$out")"
check "it holds the fresh thread, worktree, branch, model and effort" "t-9 /wt/9 feat/x-9 sonnet high" \
  "$(LR get Gharib89/skills#8 | jq -r '[.thread, .worktree, .branch, .model, .effort] | join(" ")')"
check "and starts the tracking over: launched, 0 stalls, nothing observed" "launched 0 null null 0" \
  "$(LR get Gharib89/skills#8 | jq -r '[.stage, .stalls, .observed, .rest_since, .judged_run] | map(tostring) | join(" ")')"
out=$(LR rethread Gharib89/skills#99 --thread t-9 --worktree /wt/9 --branch b 2>/dev/null); rc=$?
check_rc "rethread of a key the ledger lacks exits 1" 1 "$rc"
out=$(LR rethread Gharib89/skills#8 --thread t-9 2>/dev/null); rc=$?
check_rc "rethread without a worktree and branch exits 2" 2 "$rc"

# rethread keeps what it is not given, and replaces what it is: a triaged ticket now shipping
LR add --repo Gharib89/skills --number 10 --thread t-10 --worktree /wt/10 --branch b-10 --kind triage --area docs >/dev/null
LR rethread Gharib89/skills#10 --thread t-11 --worktree /wt/11 --branch b-11 >/dev/null
check "rethread without --kind or --area keeps both" 'triage ["docs"]' \
  "$(LR get Gharib89/skills#10 | jq -r '"\(.kind) \(.areas | tojson)"')"
LR rethread Gharib89/skills#10 --thread t-12 --worktree /wt/12 --branch b-12 --kind ship --area skills/ship --area tests >/dev/null
check "rethread with --kind and repeated --area replaces both" 'ship ["skills/ship","tests"]' \
  "$(LR get Gharib89/skills#10 | jq -r '"\(.kind) \(.areas | tojson)"')"
LR rethread Gharib89/skills#10 --thread t-13 --worktree /wt/13 --branch b-13 --kind triage >/dev/null
check "--kind alone leaves the areas" '["skills/ship","tests"]' "$(LR get Gharib89/skills#10 | jq -c .areas)"
out=$(LR rethread Gharib89/skills#10 --thread t-13 --worktree /wt/13 --branch b-13 --kind bogus 2>/dev/null); rc=$?
check_rc "rethread with a kind outside ship and triage exits 2" 2 "$rc"

# --- add over a finished entry: a triaged ticket that then ships ----------------------------
LR add --repo Gharib89/skills --number 12 --thread t-t --worktree /wt/t --branch triage-12 --kind triage >/dev/null
LR set Gharib89/skills#12 stalls 2 >/dev/null
LR set Gharib89/skills#12 observed '{"status":"idle"}' >/dev/null
out=$(LR add --repo Gharib89/skills --number 12 --thread t-s --worktree /wt/s --branch ship-12 --kind ship --area skills/x --model m --effort high 2>/dev/null); rc=$?
check_rc "add over an open entry exits 1" 1 "$rc"
check "and keeps the open entry" "t-t triage" "$(LR get Gharib89/skills#12 | jq -r '"\(.thread) \(.kind)"')"
for st in settled closed; do
  LR set Gharib89/skills#12 stage "\"$st\"" >/dev/null
  out=$(LR add --repo Gharib89/skills --number 12 --thread "t-$st" --worktree /wt/s --branch ship-12 --kind ship --area skills/x --model m --effort high); rc=$?
  check_rc "add over a $st entry exits 0" 0 "$rc"
  check "and replaces it with a fresh ship entry ($st)" "t-$st ship launched 0 null m high [\"skills/x\"]" \
    "$(LR get Gharib89/skills#12 | jq -r '[.thread, .kind, .stage, .stalls, .observed, .model, .effort, (.areas | tojson)] | map(tostring) | join(" ")')"
done

# --- areas: the paths a ticket's work touches, which placement reads ------------------
rm -f "$led"
out=$(L add --repo Gharib89/skills --number 20 --thread t-20 --worktree /wt/20 --branch b-20 --area skills/ship --area docs)
check "add takes each --area, in order" '["skills/ship","docs"]' "$(jq -c .entry.areas <<<"$out")"
check "an entry added with none holds an empty list" '[]' "$(add 21 t-21 | jq -c .entry.areas)"

# --- waiting: a ticket nothing fits holds a row, never a thread --------------------------
out=$(L wait Gharib89/skills#30 --reason "gpu: no reachable machine with a GPU"); rc=$?
check_rc "wait exits 0" 0 "$rc"
check "it answers the row" '{"key":"Gharib89/skills#30","repo":"Gharib89/skills","number":30,"reason":"gpu: no reachable machine with a GPU"}' \
  "$(jq -c '.waiting | {key, repo, number, reason}' <<<"$out")"
check "the row is dated" 1 "$(jq '.waiting.since | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T") | if . then 1 else 0 end' <<<"$out")"
check "list reads it back beside the entries" '["Gharib89/skills#30"]' "$(L list | jq -c '[.waiting[].key]')"
check "and no entry exists for it" 2 "$(L list | jq '.entries | length')"
check "a waiting row is no open entry, so no watcher reads it" 2 "$(L list --open | jq '.entries | length')"
since=$(L list | jq -r '.waiting[0].since'); sleep 1
L wait Gharib89/skills#30 --reason "no machine fits now" >/dev/null
check "a second wait replaces the reason and keeps the first since" "no machine fits now $since" \
  "$(L list | jq -r '.waiting[0] | "\(.reason) \(.since)"')"
check "there is still one row" 1 "$(L list | jq '.waiting | length')"
out=$(L wait Gharib89/skills#20 --reason x 2>/dev/null); rc=$?
check_rc "a ticket with a thread cannot wait" 1 "$rc"
check "and says so" "Gharib89/skills#20 already has a thread in the ledger" "$(jq -r .error <<<"$out")"
check_rc "a key that is no repo and number exits 2" 2 "$(L wait nope --reason x >/dev/null 2>&1; echo $?)"
check_rc "a wait with no reason exits 2" 2 "$(L wait Gharib89/skills#31 >/dev/null 2>&1; echo $?)"
L wait Gharib89/skills#32 --reason r >/dev/null
out=$(L add --repo Gharib89/skills --number 32 --thread t-32 --worktree /wt/32 --branch b-32)
check "launching a waiting ticket takes its row away" '["Gharib89/skills#30"]' "$(L list | jq -c '[.waiting[].key]')"
out=$(L unwait Gharib89/skills#30)
check "unwait removes a row and says it did" '{"key":"Gharib89/skills#30","removed":true}' "$(jq -c . <<<"$out")"
check "and a second says it had none" false "$(L unwait Gharib89/skills#30 | jq .removed)"
check "a ledger written before waiting existed lists none" '[]' \
  "$(jq 'del(.waiting)' "$led" > "$tmp/old.json" && bash "$s/ledger.sh" --ledger "$tmp/old.json" list | jq -c .waiting)"

finish
