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

# --- set: one field, the stage a closed list ------------------------------------
out=$(L set Gharib89/skills#6 stage '"running"'); rc=$?
check_rc "set stage exits 0" 0 "$rc"
check "set answers the key, field and value" '{"key":"Gharib89/skills#6","field":"stage","value":"running"}' \
  "$(jq -c '{key, field, value}' <<<"$out")"
check "the change is in the file" running "$(jq -r '.entries["Gharib89/skills#6"].stage' "$led")"
out=$(L set Gharib89/skills#6 stage '"asleep"' 2>/dev/null); rc=$?
check_rc "a stage outside the list exits 1" 1 "$rc"
check "and names the list" "stage must be one of launched, running, at-rest, settled, closed" "$(jq -r .error <<<"$out")"
check "the refused stage left the entry alone" running "$(jq -r '.entries["Gharib89/skills#6"].stage' "$led")"
L set Gharib89/skills#5 stage '"settled"' >/dev/null
check "list --open leaves settled entries out" "Gharib89/skills#6 Gharib89/skills#7" \
  "$(L list --open | jq -r '[.entries[].key] | join(" ")')"
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

finish
