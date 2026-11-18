#!/usr/bin/env bash
# super-agent's ledger writes are serialized: concurrent `ledger` writes all
# land, a write made while `reconcile` reads T3 and GitHub survives its write,
# and no script writes the ledger except through `sa_update` in _lib.sh.
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
: > "$led.lock"
out=$(SA_LOCK_TRIES=3 L ruling "behind an empty lock" 2>/dev/null); rc=$?
check_rc "a lock that reads empty is kept, and the wait ends in exit 2" 2 "$rc"
check "the refusal names the lock" "$led.lock is held by pid unknown; remove it if no ledger write runs" "$(jq -r .error <<<"$out")"
check "and the empty lock is still there" yes "$([ -f "$led.lock" ] && [ ! -s "$led.lock" ] && echo yes)"
printf '%s\n' "$$" > "$led.lock"
out=$(SA_LOCK_TRIES=3 L ruling "behind a live lock" 2>/dev/null); rc=$?
check_rc "a live holder outlasting the wait is exit 2" 2 "$rc"
check "the refusal names its pid" "$led.lock is held by pid $$; remove it if no ledger write runs" "$(jq -r .error <<<"$out")"
check "and neither write landed" "after a crash" "$(jq -r '.rulings[].text' "$led")"
rm -f "$led.lock"
for bad in x 0 08; do
  out=$(SA_LOCK_TRIES=$bad L ruling "with a bad try count" 2>/dev/null); rc=$?
  check_rc "SA_LOCK_TRIES=$bad is refused with exit 2" 2 "$rc"
  check "and the refusal says why" "SA_LOCK_TRIES must be a whole number of 1 or more" "$(jq -r .error <<<"$out")"
done
check "a refused try count writes nothing" "after a crash" "$(jq -r '.rulings[].text' "$led")"

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
  bash "$PWD/$s/ledger.sh" --ledger "$led" need "$repo#5" --action "answer it" >/dev/null
fi
exec "$tmp/bin/gh" "\$@"
EOF
chmod +x "$tmp/mid/gh"
out=$(PATH="$tmp/mid:$PATH" bash "$s/reconcile.sh" --ledger "$led"); rc=$?
check_rc "reconcile exits 0" 0 "$rc"
check "the ruling made mid-reconcile survives it" "made mid-reconcile" "$(jq -r '.rulings[].text' "$led")"
check "the need made mid-reconcile survives it" "answer it" "$(jq -r '.needs[].action' "$led")"
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

# --- no script writes the ledger but sa_update -----------------------------------
# sa_write is the bare write; outside _lib.sh it may name only the fleet and
# quota files, never a ledger.
check "sa_write names no ledger outside sa_update" "" \
  "$(grep -rn 'sa_write' "$s" | grep -v "^$s/_lib.sh:" | grep -v 'sa_write "\$fleet' | grep -v 'sa_write "\$fleet_file"' | grep -v 'sa_write "\$save"')"
check "nothing redirects into a ledger" "" "$(grep -rnE '>>? *"\$(ledger|led|1)"' "$s")"

finish
