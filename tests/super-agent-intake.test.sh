#!/usr/bin/env bash
# super-agent's `intake` (the daily offer), driven through its command line over
# a fleet file, a ledger and the fake `gh`: only active repos are scanned, only
# open `ready-for-agent` issues that are no PR are offered, a ticket the ledger
# holds or another machine claims is left out and named, a stale claim is
# listed rather than offered, and the offer writes and launches nothing.
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
fleet=$tmp/fleet.json led=$tmp/ledger.json
I() { bash "$s/intake.sh" --fleet "$fleet" --ledger "$led" --machine alpha --thread th-a --now 2026-11-06T12:00:00Z; }
issues() { # <repo> <json array>: the ready-for-agent list of a repo
  sa_route "repos/$1/issues?state=open&labels=ready-for-agent&per_page=100" "$2"
}
issue() { jq -cn --argjson n "$1" --arg t "$2" --argjson pr "${3:-false}" \
  '{number: $n, title: $t, labels: [{name: "ready-for-agent"}, {name: "M"}]} + (if $pr then {pull_request: {}} else {} end)'; }
claim() { # <repo> <number> <machine> <created_at>
  sa_route "repos/$1/issues/$2/comments" "[$(jq -cn --arg m "$3" --arg t "$4" \
    '{id: 11, created_at: $t, user: {login: "octo"}, body: "<!-- super-agent-claim machine=\($m) thread=th-\($m) -->\nClaimed."}')]"
}
reset() {
  rm -f "$SA_FAKE/calls" "$led"; sa_route user '{"login":"octo"}'
  printf '%s\n' '{"machines":{"alpha":{}},"active_repos":["acme/widgets","acme/gadgets"]}' > "$fleet"
  issues acme/widgets "[$(issue 3 'Third'),$(issue 1 'First'),$(issue 2 'A pull request' true)]"
  issues acme/gadgets "[$(issue 9 'Gadget')]"
  for n in 1 3; do sa_route "repos/acme/widgets/issues/$n/comments" '[]'; done
  sa_route repos/acme/gadgets/issues/9/comments '[]'
}

# --- the contract every script keeps ------------------------------------------
out=$(bash "$s/intake.sh" --help 2>"$tmp/err"); rc=$?
check "--help opens with its usage line" "usage: intake" "$(sed -n 1p <<<"$out" | cut -d' ' -f1-2)"
check "--help names its stdout fields next" stdout: "$(sed -n 2p <<<"$out" | cut -c1-7)"
check_rc "--help exits 0" 0 "$rc"
check "--help writes nothing on stderr" "" "$(cat "$tmp/err")"
out=$(bash "$s/intake.sh" --bogus 2>/dev/null); rc=$?
check "a bad flag answers the usage line" "$(sed -n 1p <<<"$(bash "$s/intake.sh" --help)")" "$(jq -r .error <<<"$out")"
check_rc "a bad flag exits 2" 2 "$rc"
check_rc "a missing thread exits 2" 2 "$(bash "$s/intake.sh" --fleet "$fleet" --ledger "$led" --machine alpha >/dev/null 2>&1; echo $?)"

# --- the offer: active repos only, issues only, by number ---------------------------
reset
out=$(I); rc=$?
check_rc "an offer exits 0" 0 "$rc"
check "the active repos are the ones scanned" '["acme/widgets","acme/gadgets"]' "$(jq -c .repos <<<"$out")"
check "the offer lists issues, not pull requests, repos in the file's order and tickets by number" \
  '["acme/widgets#1","acme/widgets#3","acme/gadgets#9"]' "$(jq -c '[.offer[].key]' <<<"$out")"
check "each carries its title and labels" '{"key":"acme/widgets#1","title":"First","labels":["ready-for-agent","M"]}' "$(jq -c '.offer[0]' <<<"$out")"
check "nothing is held, claimed, stale or errored" '{"held":[],"claimed":[],"stale":[],"errors":[]}' \
  "$(jq -c '{held, claimed, stale, errors}' <<<"$out")"

# --- a repo that is not active is never read ------------------------------------------
reset
sa_route "repos/acme/other/issues?state=open&labels=ready-for-agent&per_page=100" "[$(issue 5 'Elsewhere')]"
I >/dev/null
check "an inactive repo's issues are never asked for" 0 "$(grep -c acme/other "$SA_FAKE/calls")"
bash "$s/track.sh" --fleet "$fleet" stop acme/gadgets >/dev/null
out=$(I)
check "a repo stopped tracking leaves the offer" '["acme/widgets#1","acme/widgets#3"]' "$(jq -c '[.offer[].key]' <<<"$out")"
check "and the scan" '["acme/widgets"]' "$(jq -c .repos <<<"$out")"
bash "$s/track.sh" --fleet "$fleet" track acme/other >/dev/null
check "a repo tracked joins it" '["acme/widgets#1","acme/widgets#3","acme/other#5"]' \
  "$(sa_route repos/acme/other/issues/5/comments '[]'; I | jq -c '[.offer[].key]')"
printf '%s\n' '{"machines":{"alpha":{}}}' > "$fleet"
out=$(I); rc=$?
check_rc "a fleet file with no active repos is an empty offer, exit 0" 0 "$rc"
check "which names nothing" '{"repos":[],"offer":[]}' "$(jq -c '{repos, offer}' <<<"$out")"

# --- a ticket the ledger holds -----------------------------------------------------------
reset
bash "$s/ledger.sh" --ledger "$led" add --repo acme/widgets --number 1 --thread t-1 --worktree /wt/1 --branch b-1 >/dev/null
out=$(I)
check "an open ledger entry is held, not offered" '{"held":["acme/widgets#1"],"offer":["acme/widgets#3","acme/gadgets#9"]}' \
  "$(jq -c '{held, offer: [.offer[].key]}' <<<"$out")"
sa_stage "$led" acme/widgets#1 settled
check "a settled entry is no hold" '["acme/widgets#1","acme/widgets#3","acme/gadgets#9"]' "$(I | jq -c '[.offer[].key]')"
bash "$s/ledger.sh" --ledger "$led" add --repo Acme/Gadgets --number 9 --thread t-9 --worktree /wt/9 --branch b-9 >/dev/null
check "a ledger key in another case still holds the ticket" '["acme/gadgets#9"]' "$(I | jq -c .held)"

# --- another machine's claim ------------------------------------------------------------------
reset
claim acme/widgets 1 beta 2026-11-06T09:00:00Z
claim acme/widgets 3 beta 2026-11-01T12:00:00Z
out=$(I)
check "a fresh claim by another machine is listed with its holder and age, not offered" '{"claimed":[{"key":"acme/widgets#1","machine":"beta","age_s":10800}],"offer":["acme/gadgets#9"]}' \
  "$(jq -c '{claimed, offer: [.offer[].key]}' <<<"$out")"
check "a stale claim is listed apart, never offered" '[{"key":"acme/widgets#3","machine":"beta","age_s":432000}]' "$(jq -c .stale <<<"$out")"
claim acme/widgets 1 alpha 2026-11-01T12:00:00Z
check "this machine's own claim is no obstacle" '["acme/widgets#1","acme/gadgets#9"]' "$(I | jq -c '[.offer[].key]')"

# --- it launches nothing and writes nothing ----------------------------------------------------
reset
claim acme/widgets 3 beta 2026-11-01T12:00:00Z
I >/dev/null
check "no POST or DELETE reached GitHub" 0 "$(grep -c -- '-X POST\|-X DELETE' "$SA_FAKE/calls")"
check "and no t3 call was made" 0 "$(grep -c '^t3 ' "$SA_FAKE/calls")"
check "and the ledger was never created" no "$([ -f "$led" ] && echo yes || echo no)"

# --- what cannot be read is named, the rest still offered --------------------------------------
reset
rm -f "$SA_FAKE/gh/repos_acme_gadgets_issues_state_open_labels_ready-for-agent_per_page_100"
out=$(I); rc=$?
check_rc "an unreadable repo still exits 0" 0 "$rc"
check "it is named in errors" '[{"repo":"acme/gadgets","error":"cannot read its ready-for-agent issues"}]' "$(jq -c .errors <<<"$out")"
check "and the other repo is still offered" '["acme/widgets#1","acme/widgets#3"]' "$(jq -c '[.offer[].key]' <<<"$out")"
reset
rm -f "$SA_FAKE/gh/repos_acme_widgets_issues_3_comments"
out=$(I)
check "a ticket whose claim cannot be read is named, never offered" '{"errors":[{"key":"acme/widgets#3","error":"cannot read its claim"}],"offer":["acme/widgets#1","acme/gadgets#9"]}' \
  "$(jq -c '{errors, offer: [.offer[].key]}' <<<"$out")"

finish
