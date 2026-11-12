#!/usr/bin/env bash
# super-agent's `launch-check`, driven through its command line over a fleet file
# and a ledger: each threshold refuses on its own (slots, load, RAM), a launch
# passes when all hold, the slot kept for the owner's messages is not spent, and
# two tickets of one repo run side by side only apart.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
fleet=$tmp/fleet.json led=$tmp/ledger.json
cat > "$fleet" <<'JSON'
{"thread_ram_floor_gb": 4,
 "machines": {"home": {"cores": 8, "slots": 3, "reserve": 1, "max_load": 8},
              "box": {"environment_id": "env-box", "cores": 4, "slots": 2, "max_load": 4}}}
JSON
LC() { bash "$s/launch-check.sh" --fleet "$fleet" --ledger "$led" --own home "$@"; }
add() { # <repo> <number> <machine> [--area ...]
  local r=$1 n=$2 m=$3; shift 3
  bash "$s/ledger.sh" --ledger "$led" add --repo "$r" --number "$n" --thread "t-$n" --worktree "/wt/$n" --branch "b-$n" --machine "$m" "$@" >/dev/null
}

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/launch-check.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: launch-check" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/launch-check.sh" --bogus 2>/dev/null); rc=$?
check "a bad flag answers the usage line" "$(sed -n 1p <<<"$(bash "$s/launch-check.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad flag exits 2" 2 "$rc"
out=$(LC --machine box --load abc --free-gb 8 2>/dev/null); rc=$?
check_rc "a load that is no number exits 2" 2 "$rc"

# --- all thresholds hold: accepted ----------------------------------------------
out=$(LC --machine box --load 1.5 --free-gb 8); rc=$?
check_rc "an idle machine with a free slot is accepted" 0 "$rc"
check "and nothing is refused" '{"ok":true,"refused":[]}' "$(jq -c '{ok, refused}' <<<"$out")"
check "the answer carries each reading against its limit" \
  '{"slots":{"used":0,"ceiling":2},"load":{"value":1.5,"limit":4},"free_gb":{"value":8,"floor":4}}' \
  "$(jq -c '{slots, load, free_gb}' <<<"$out")"

# --- each threshold refuses on its own --------------------------------------------
out=$(LC --machine box --load 4 --free-gb 8); rc=$?
check_rc "a load at the core count exits 1" 1 "$rc"
check "and only the load is refused" '["load"]' "$(jq -c .refused <<<"$out")"
check "a load just under it is accepted" 0 "$(LC --machine box --load 3.9 --free-gb 8 >/dev/null; echo $?)"
out=$(LC --machine box --load 1 --free-gb 4); rc=$?
check_rc "free RAM at the floor exits 1" 1 "$rc"
check "and only RAM is refused" '["ram"]' "$(jq -c .refused <<<"$out")"
check "free RAM just above it is accepted" 0 "$(LC --machine box --load 1 --free-gb 4.1 >/dev/null; echo $?)"
add Gharib89/skills 1 box; add Gharib89/other 2 box
out=$(LC --machine box --load 1 --free-gb 8); rc=$?
check_rc "a machine at its slot ceiling exits 1" 1 "$rc"
check "and only the slots are refused" '["slots"]' "$(jq -c .refused <<<"$out")"
check "it counts the entries on the machine" '{"used":2,"ceiling":2}' "$(jq -c .slots <<<"$out")"
out=$(LC --machine box --load 9 --free-gb 1)
check "every threshold that fails is named" '["slots","load","ram"]' "$(jq -c .refused <<<"$out")"
sa_stage "$led" Gharib89/skills#1 settled
check "a settled entry holds no slot" 0 "$(LC --machine box --load 1 --free-gb 8 >/dev/null; echo $?)"

# --- the slot kept for the owner's messages ------------------------------------------
check "this machine's ceiling is its slots less its reserve" 2 "$(LC --machine home --load 1 --free-gb 8 | jq .slots.ceiling)"
add Gharib89/a 10 home; add Gharib89/b 11 local
out=$(LC --machine home --load 1 --free-gb 8)
check "an entry added with the machine local counts here" 2 "$(jq .slots.used <<<"$out")"
check "so the reserved slot is never launched into" '["slots"]' "$(jq -c .refused <<<"$out")"
check "while a linked machine does not count a local entry" 1 "$(LC --machine box --load 1 --free-gb 8 | jq .slots.used)"

# --- a machine the fleet file lacks --------------------------------------------------
out=$(LC --machine nowhere --load 1 --free-gb 8 2>/dev/null); rc=$?
check_rc "an unknown machine exits 1" 1 "$rc"
check "and is named" "nowhere is not in the fleet file" "$(jq -r .error <<<"$out")"

# --- the same repo runs beside itself only apart -----------------------------------
rm -f "$led"
add Gharib89/skills 1 box --area skills/ship; add Gharib89/other 2 box --area skills/ship
R() { LC --machine home --load 1 --free-gb 8 --repo Gharib89/skills "$@"; }
check "a ticket of another repo never conflicts, whatever its areas" '[]' \
  "$(R --area skills/ship | jq -c '.repo.conflicts // []' | jq -c 'map(select(test("other")))')"
out=$(R --area skills/ship/scripts); rc=$?
check_rc "an area under an open ticket's area is refused" 1 "$rc"
check "and names the ticket in the way" '["Gharib89/skills#1"]' "$(jq -c .repo.conflicts <<<"$out")"
check "the refusal is the repo's" '["repo"]' "$(jq -c .refused <<<"$out")"
check "an area above it overlaps too" 1 "$(R --area skills >/dev/null; echo $?)"
check "the same area overlaps" 1 "$(R --area skills/ship >/dev/null; echo $?)"
check "an apart area runs beside it" 0 "$(R --area skills/drive-session >/dev/null; echo $?)"
check "a sibling sharing only a name prefix is apart" 0 "$(R --area skills/ship-extra >/dev/null; echo $?)"
check "a trailing slash on either side does not hide an overlap" 1 "$(R --area skills/ship/scripts/ >/dev/null; echo $?)"
check "nor does a leading ./" 1 "$(R --area ./skills/ship/scripts >/dev/null; echo $?)"
check "no area at all overlaps everything, since nothing says it is apart" 1 "$(R >/dev/null; echo $?)"
add Gharib89/skills 3 box
check "an open ticket with no areas blocks a same-repo launch" 1 "$(R --area skills/drive-session >/dev/null; echo $?)"
rm -f "$led"
add Gharib89/skills 1 box --area skills/ship
check "a blocking edge to an open ticket refuses even apart" 1 "$(R --area docs --blocked-by 1 >/dev/null; echo $?)"
check "an edge to a ticket not open here refuses nothing" 0 "$(R --area docs --blocked-by 9 >/dev/null; echo $?)"
sa_stage "$led" Gharib89/skills#1 settled
check "a settled ticket is out of the way" 0 "$(R --area skills/ship >/dev/null; echo $?)"


# --- the repo's ship cap: every open ticket of the repo, ship and triage, on any machine ---
rm -f "$led"
K() { LC --machine box --load 1 --free-gb 8 --repo Gharib89/skills --area docs "$@"; }
add Gharib89/skills 1 home --area a; add Gharib89/skills 2 home --area b --kind triage
out=$(K); rc=$?
check_rc "two open tickets of the repo are under the default cap of 3" 0 "$rc"
check "the answer reports the count against the cap" '{"open":2,"max":3}' "$(jq -c .cap <<<"$out")"
add Gharib89/skills 3 box --area c
out=$(K); rc=$?
check_rc "three open tickets (a triage one among them, one on another machine) refuse the fourth" 1 "$rc"
check "the refusal is the cap, and only it" '["cap"]' "$(jq -c .refused <<<"$out")"
check "another repo is not counted" 0 "$(LC --machine box --load 1 --free-gb 8 --repo Gharib89/other --area docs >/dev/null; echo $?)"
check "a settled ticket stops counting" 0 "$(sa_stage "$led" Gharib89/skills#3 settled; K >/dev/null; echo $?)"
check "--key leaves its own entry out of the count" 0 "$(add Gharib89/skills 3 box --area c 2>/dev/null; K --key Gharib89/skills#3 >/dev/null; echo $?)"
jq '.repos = {"gharib89/SKILLS": {"max_ships": 2}}' "$fleet" > "$tmp/capped.json"
check "a repo's max_ships from the fleet file wins, its key matched without case" '["cap"]' \
  "$(bash "$s/launch-check.sh" --fleet "$tmp/capped.json" --ledger "$led" --own home --machine box --load 1 --free-gb 8 --repo Gharib89/skills --area docs | jq -c .refused)"
jq '.repos = {"Gharib89/skills": {"max_ships": 5}}' "$fleet" > "$tmp/capped.json"
check "and a higher one lets the launch through" 0 "$(bash "$s/launch-check.sh" --fleet "$tmp/capped.json" --ledger "$led" --own home --machine box --load 1 --free-gb 8 --repo Gharib89/skills --area docs >/dev/null; echo $?)"
jq '.repos = {"Gharib89/skills": {"max_ships": 0}}' "$fleet" > "$tmp/capped.json"
check_rc "a max_ships that is not a whole number of 1 or more exits 2" 2 "$(bash "$s/launch-check.sh" --fleet "$tmp/capped.json" --ledger "$led" --own home --machine box --load 1 --free-gb 8 --repo Gharib89/skills >/dev/null 2>&1; echo $?)"

# a ledger over 128 KiB (Linux's one-argument cap) is read the same as a small one
rm -f "$led"; add Gharib89/skills 1 box
small=$(LC --machine box --load 1 --free-gb 8 | jq -c '{ok, refused, slots}')
jq -c '.pad = ("x" * 140000)' "$led" > "$tmp/big.json" && mv "$tmp/big.json" "$led"
check "the test ledger is over 128 KiB" true "$([ "$(wc -c < "$led")" -gt 131072 ] && echo true)"
out=$(LC --machine box --load 1 --free-gb 8 2>"$tmp/err"); rc=$?
check_rc "a ledger over 128 KiB is read" 0 "$rc"
check "and answers as the small ledger did" "$small" "$(jq -c '{ok, refused, slots}' <<<"$out")"
# a fleet file that is not JSON is refused by its own name, not the ledger's
printf 'not json\n' > "$tmp/badjson.json"
out=$(bash "$s/launch-check.sh" --fleet "$tmp/badjson.json" --ledger "$led" --own home --machine box --load 1 --free-gb 8 2>/dev/null); rc=$?
check_rc "a fleet file that is not JSON exits 2" 2 "$rc"
check "and the error names the fleet file" true "$(jq -r --arg f "$tmp/badjson.json" '.error | startswith($f)' <<<"$out")"

finish
