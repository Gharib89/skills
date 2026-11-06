#!/usr/bin/env bash
# super-agent's `claim`, driven through its command line over the fake `gh`
# (tests/super-agent-fake.sh): a fresh claim assigns the ticket and posts a
# claim comment naming the machine and thread, an existing claim is reported
# with its age and never taken, a claim past the stale window is `stale`, the
# same machine's claim is its own, two claims posted together resolve to the
# earlier one, and --check writes nothing.
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
repo=acme/widgets
ep=repos/$repo/issues/7/comments
C() { bash "$s/claim.sh" --repo "$repo" --number 7 --machine alpha --thread th-a --now 2026-11-06T12:00:00Z "$@"; }
reset() { rm -f "$SA_FAKE/calls" "$SA_FAKE/on-post"; sa_route "$ep" '[]'; sa_route user '{"login":"octo"}'; echo 2026-11-06T12:00:00Z > "$SA_FAKE/now"; }
writes() { grep -c -- '-X POST\|-X DELETE' "$SA_FAKE/calls" 2>/dev/null || true; }
rival() { # <id> <machine> <created_at>: a claim comment of another machine
  jq -cn --argjson i "$1" --arg m "$2" --arg t "$3" \
    '{id: $i, created_at: $t, body: "<!-- super-agent-claim machine=\($m) thread=th-\($m) -->\nClaimed."}'
}

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/claim.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: claim" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/claim.sh" --bogus 2>/dev/null); rc=$?
check "a bad flag answers the usage line" "$(sed -n 1p <<<"$(bash "$s/claim.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad flag exits 2" 2 "$rc"
check_rc "a missing thread exits 2" 2 "$(bash "$s/claim.sh" --repo $repo --number 7 --machine alpha >/dev/null 2>&1; echo $?)"
check_rc "a repo that is no owner/name exits 2" 2 "$(bash "$s/claim.sh" --repo widgets --number 7 --machine alpha --thread t >/dev/null 2>&1; echo $?)"
check_rc "a stale window of 0 exits 2" 2 "$(C --stale-after 0 >/dev/null 2>&1; echo $?)"

# --- a fresh claim ----------------------------------------------------------------
reset
out=$(C); rc=$?
check_rc "a free ticket is taken, exit 0" 0 "$rc"
check "the answer is taken, naming machine and thread" '{"status":"taken","machine":"alpha","thread":"th-a","age_s":0}' \
  "$(jq -c '{status, machine: .claim.machine, thread: .claim.thread, age_s: .claim.age_s}' <<<"$out")"
check "the claim comment names machine and thread on its first line" \
  '<!-- super-agent-claim machine=alpha thread=th-a -->' "$(jq -r '.[0].body | split("\n")[0]' "$SA_FAKE/gh/$(printf '%s' "$ep" | sed 's/[^A-Za-z0-9._-]/_/g')")"
check "and the ticket is assigned to the signed-in account" 1 "$(grep -c 'POST repos/acme/widgets/issues/7/assignees -f assignees\[\]=octo' "$SA_FAKE/calls")"
check "a second call finds the claim its own" own "$(C | jq -r .status)"
check "and re-assigns, which repairs a claim whose assignment failed, but posts no second comment" '1 2' \
  "$(grep -c 'POST repos/acme/widgets/issues/7/comments' "$SA_FAKE/calls") $(grep -c 'POST repos/acme/widgets/issues/7/assignees' "$SA_FAKE/calls")"
check "--check on its own claim assigns nothing" 2 "$(C --check >/dev/null; grep -c 'POST repos/acme/widgets/issues/7/assignees' "$SA_FAKE/calls")"

# --- another machine's claim: reported with its age, never taken --------------------
reset
sa_route "$ep" "[$(rival 11 beta 2026-11-06T09:00:00Z)]"
out=$(C); rc=$?
check_rc "a claim by another machine exits 1" 1 "$rc"
check "it is claimed, with the holder and its age in seconds" '{"status":"claimed","machine":"beta","thread":"th-beta","age_s":10800}' \
  "$(jq -c '{status, machine: .claim.machine, thread: .claim.thread, age_s: .claim.age_s}' <<<"$out")"
check "nothing is posted, deleted or assigned" 0 "$(writes)"

# --- a stale claim: reported, never taken --------------------------------------------
reset
sa_route "$ep" "[$(rival 11 beta 2026-11-01T12:00:00Z)]"
out=$(C); rc=$?
check_rc "a claim past the default 3 days exits 1" 1 "$rc"
check "it is stale, with its age" '{"status":"stale","age_s":432000}' "$(jq -c '{status, age_s: .claim.age_s}' <<<"$out")"
check "and nothing is written, so the claim is not taken over" 0 "$(writes)"
check "a window shorter than the age makes a fresh claim stale" stale \
  "$(sa_route "$ep" "[$(rival 11 beta 2026-11-06T09:00:00Z)]"; C --stale-after 3600 | jq -r .status)"
check "a window longer than the age keeps it claimed" claimed \
  "$(C --stale-after 86400 | jq -r .status)"
check "the stale window is reported" 86400 "$(C --stale-after 86400 | jq .stale_after)"

# --- the same machine's claim is its own, found by any thread --------------------------
reset
sa_route "$ep" "[$(rival 11 alpha 2026-11-01T12:00:00Z)]"
out=$(C --thread th-restarted); rc=$?
check_rc "an old claim of this machine exits 0" 0 "$rc"
check "it is own, however old and whichever thread" own "$(jq -r .status <<<"$out")"

# --- comments that are no claim are ignored --------------------------------------------
reset
sa_route "$ep" '[{"id":3,"created_at":"2026-11-06T08:00:00Z","body":"claimed? <!-- super-agent-claim machine=beta thread=x -->"},{"id":4,"created_at":"2026-11-06T08:00:00Z","body":"looks good"}]'
check "a mention of the marker mid-comment is no claim" taken "$(C | jq -r .status)"

# --- two claims posted together: the earlier comment holds it ---------------------------
reset
printf '%s\n' "sa_rival=\$(cat <<'J'
$(rival 500 beta 2026-11-06T11:59:59Z)
J
)
f=\$SA_FAKE/gh/$(printf '%s' "$ep" | sed 's/[^A-Za-z0-9._-]/_/g')
jq -c --argjson c \"\$sa_rival\" '. + [\$c]' \"\$f\" > \"\$f.new\" && mv \"\$f.new\" \"\$f\"" > "$SA_FAKE/on-post"
out=$(C); rc=$?
check_rc "losing the race exits 1" 1 "$rc"
check "the holder is the earlier claim" '{"status":"claimed","machine":"beta"}' "$(jq -c '{status, machine: .claim.machine}' <<<"$out")"
check "the loser deleted its own comment" '[500]' \
  "$(jq -c '[.[].id]' "$SA_FAKE/gh/$(printf '%s' "$ep" | sed 's/[^A-Za-z0-9._-]/_/g')")"
check "and assigned nothing" 0 "$(grep -c assignees "$SA_FAKE/calls")"

# --- --check writes nothing ------------------------------------------------------------
reset
out=$(C --check); rc=$?
check_rc "--check on a free ticket exits 0" 0 "$rc"
check "it reports free, with no claim" '{"status":"free","claim":null}' "$(jq -c '{status, claim}' <<<"$out")"
check "and writes nothing" 0 "$(writes)"
sa_route "$ep" "[$(rival 11 beta 2026-11-06T09:00:00Z)]"
check "--check still reports another machine's claim" claimed "$(C --check | jq -r .status)"

# --- a host that refuses ------------------------------------------------------------------
reset
rm -f "$SA_FAKE/gh/$(printf '%s' "$ep" | sed 's/[^A-Za-z0-9._-]/_/g')"
out=$(C 2>/dev/null); rc=$?
check_rc "an unreadable comment list exits 2" 2 "$rc"
check "and writes nothing" 0 "$(writes)"

finish
