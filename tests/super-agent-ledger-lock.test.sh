#!/usr/bin/env bash
# super-agent's ledger writes are serialized: concurrent `ledger` writes all
# land, a write made while `reconcile` reads T3 and GitHub survives its write,
# and no script writes the ledger except through `sa_update` in lib/ledger-io.sh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fake"
export PATH="$tmp/bin:$PATH" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
led=$tmp/ledger.json
repo=Gharib89/skills
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }

# --- concurrent writes all land ------------------------------------------------
n=8
for i in $(seq "$n"); do L ruling "ruling $i" >/dev/null & done
wait
check "$n concurrent rulings all land" "$n" "$(jq '.rulings | length' "$led")"
rm -f "$led"
for i in $(seq "$n"); do L wait "$repo#$i" --reason busy >/dev/null & done
wait
check "$n concurrent waiting rows all land" "$n" "$(jq '.waiting | length' "$led")"

# --- the lock itself ------------------------------------------------------------
rm -f "$led"
bash -c 'exit 0' & dead=$!; wait "$dead"
printf '%s\n' "$dead" > "$led.lock"
L ruling "after a crash" >/dev/null; rc=$?
check_rc "a dead writer's lock is taken over" 0 "$rc"
check "and the write lands" "after a crash" "$(jq -r '.rulings[].text' "$led")"
check "the lock is gone once the write ends" "" "$(ls "$led".lock* 2>/dev/null)"
# A takeover cut short leaves its marker; the refusal names both files.
bash -c 'exit 0' & dead=$!; wait "$dead"
printf '%s\n' "$dead" > "$led.lock"; : > "$led.lock.takeover"
out=$(SA_LOCK_TRIES=3 L ruling "behind a cut-short takeover" 2>/dev/null); rc=$?
check_rc "a dead lock beside a leftover takeover marker is exit 2" 2 "$rc"
check "the refusal names both files" "$led.lock is held by pid $dead and a takeover was cut short; remove $led.lock and $led.lock.takeover if no ledger write runs" "$(jq -r .error <<<"$out")"
rm -f "$led.lock" "$led.lock.takeover"
# A pid reused after a kill or a reboot by a process that is no ledger writer.
sleep 30 & other=$!
printf '%s\n' "$other" > "$led.lock"
SA_LOCK_TRIES=3 L ruling "past a reused pid" >/dev/null; rc=$?
kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
check_rc "a lock whose live pid runs no super-agent script is taken over" 0 "$rc"
check "and that write lands" "past a reused pid" "$(jq -r '.rulings[-1].text' "$led")"
: > "$led.lock"
out=$(SA_LOCK_TRIES=3 L ruling "behind an empty lock" 2>/dev/null); rc=$?
check_rc "a lock that reads empty is kept, and the wait ends in exit 2" 2 "$rc"
check "the refusal names the lock" "$led.lock is held by pid unknown; remove it if no ledger write runs" "$(jq -r .error <<<"$out")"
check "and the empty lock is still there" yes "$([ -f "$led.lock" ] && [ ! -s "$led.lock" ] && echo yes)"
# A live writer started by a relative path (`bash ledger.sh` from its folder).
mkdir -p "$tmp/rel"; printf 'sleep 30\n' > "$tmp/rel/ledger.sh"
(cd "$tmp/rel" && exec bash ledger.sh) & holder=$!
sleep 0.2
printf '%s\n' "$holder" > "$led.lock"
out=$(SA_LOCK_TRIES=3 L ruling "behind a live lock" 2>/dev/null); rc=$?
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
check_rc "a live holder run by a relative path, outlasting the wait, is exit 2" 2 "$rc"
check "the refusal names its pid" "$led.lock is held by pid $holder; remove it if no ledger write runs" "$(jq -r .error <<<"$out")"
check "and neither write landed" "past a reused pid" "$(jq -r '.rulings[-1].text' "$led")"
rm -f "$led.lock"
for bad in x 0 08; do
  out=$(SA_LOCK_TRIES=$bad L ruling "with a bad try count" 2>/dev/null); rc=$?
  check_rc "SA_LOCK_TRIES=$bad is refused with exit 2" 2 "$rc"
  check "and the refusal says why" "SA_LOCK_TRIES must be a whole number of 1 or more" "$(jq -r .error <<<"$out")"
done
check "a refused try count writes nothing" "past a reused pid" "$(jq -r '.rulings[-1].text' "$led")"

# --- a write made while reconcile runs survives it -----------------------------
rm -f "$led"
L add --repo $repo --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null
sa_thread t-5 running 1 0 /wt/5 feat/x-5
sa_pr $repo feat/x-5 none
sa_issue $repo 5 open
# The first gh call reconcile makes records a ruling and a need first, as the
# owner's super agent would while reconcile waits on GitHub.
mkdir -p "$tmp/mid"
cat > "$tmp/mid/gh" <<EOF
#!/usr/bin/env bash
if [ ! -f "$tmp/mid/done" ]; then
  : > "$tmp/mid/done"
  bash "$PWD/$s/ledger.sh" --ledger "$led" ruling "made mid-reconcile" >/dev/null
  bash "$PWD/$s/ledger.sh" --ledger "$led" need "$repo#5" --action "Answer ${repo#*/}#5 now" --reason fault --why w --option a --option b >/dev/null
fi
exec "$tmp/bin/gh" "\$@"
EOF
chmod +x "$tmp/mid/gh"
out=$(PATH="$tmp/mid:$PATH" bash "$s/reconcile.sh" --ledger "$led"); rc=$?
check_rc "reconcile exits 0" 0 "$rc"
check "the ruling made mid-reconcile survives it" "made mid-reconcile" "$(jq -r '.rulings[].text' "$led")"
check "the need made mid-reconcile survives it" "Answer skills#5 now" "$(jq -r '.needs[].action' "$led")"
check "and reconcile's own change still lands" running "$(jq -r --arg k "$repo#5" '.entries[$k].stage' "$led")"

# A rethread made mid-reconcile is not overwritten with the old thread's reading.
rm -f "$led" "$tmp/mid/done"
L add --repo $repo --number 5 --thread t-5 --worktree /wt/5 --branch feat/x-5 >/dev/null
cat > "$tmp/mid/gh" <<EOF
#!/usr/bin/env bash
if [ ! -f "$tmp/mid/done" ]; then
  : > "$tmp/mid/done"
  bash "$PWD/$s/ledger.sh" --ledger "$led" rethread "$repo#5" --thread t-9 --worktree /wt/9 --branch feat/x-9 >/dev/null
fi
exec "$tmp/bin/gh" "\$@"
EOF
PATH="$tmp/mid:$PATH" bash "$s/reconcile.sh" --ledger "$led" >/dev/null
check "a rethread made mid-reconcile keeps its fresh tracking" "t-9 launched null" \
  "$(jq -r --arg k "$repo#5" '.entries[$k] | "\(.thread) \(.stage) \(.observed)"' "$led")"

# A waiting row whose issue closed is dropped even when another write re-spelled
# its key, in another case, while reconcile read GitHub.
rm -f "$led" "$tmp/mid/done"
L wait "$repo#7" --reason busy >/dev/null
sa_issue $repo 7 closed
cat > "$tmp/mid/gh" <<EOF
#!/usr/bin/env bash
if [ ! -f "$tmp/mid/done" ]; then
  : > "$tmp/mid/done"
  bash "$PWD/$s/ledger.sh" --ledger "$led" wait "GHARIB89/Skills#7" --reason "still busy" >/dev/null
fi
exec "$tmp/bin/gh" "\$@"
EOF
out=$(PATH="$tmp/mid:$PATH" bash "$s/reconcile.sh" --ledger "$led"); rc=$?
check_rc "reconcile exits 0 over a re-spelled waiting row" 0 "$rc"
check "reconcile reports the row dropped" "$repo#7" "$(jq -r '.dropped[].key' <<<"$out")"
check "and the re-spelled row is dropped with it" 0 "$(jq '.waiting | length' "$led")"

# A status whose merged_ack is no array is refused by name before the write.
printf '%s\n' '{"entries":{},"rulings":[],"status":{"merged_ack":"x"}}' > "$led"
out=$(bash "$s/status.sh" --ledger "$led" --digest 2>/dev/null); rc=$?
check_rc "status refuses a merged_ack that is no array" 2 "$rc"
check "and names the field" "$led: status is not an object with a merged_ack array" "$(jq -r .error <<<"$out")"

# --- no script writes the ledger but sa_update -----------------------------------
# sa_write is the bare write; outside lib/ledger-io.sh it may name only the fleet and
# quota files and the super agent folder's settings (the hooks, the cut and its
# skills.json), never a ledger.
check "sa_write names no ledger outside sa_update" "" \
  "$(grep -rn 'sa_write' "$s" | grep -v "^$s/lib/ledger-io.sh:" | grep -v 'sa_write "\$fleet' | grep -v 'sa_write "\$fleet_file"' | grep -v 'sa_write "\$save"' \
    | grep -vE "^$s/lib/home.sh:.*\(sa_write \"(\\\$settings|\\\$cut_file|\\\$\(sa_home_skills\))\"")"
check "nothing redirects into a ledger" "" "$(grep -rnE '>>? *"\$(ledger|led|1)"' "$s")"

finish
