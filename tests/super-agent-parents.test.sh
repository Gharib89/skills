#!/usr/bin/env bash
# super-agent's `parents_done`, driven through `reconcile`'s command line over fake
# `t3` and `gh` on PATH (tests/super-agent-fake.sh): a merged ship ticket that is a
# sub-issue gets one look at its parent, and a parent whose sub-issues are all
# closed is offered once, never closed.
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
R() { bash "$s/reconcile.sh" --ledger "$led"; }
L() { bash "$s/ledger.sh" --ledger "$led" "$@"; }
calls() { cat "$SA_FAKE/calls" 2>/dev/null; }

# fixture: tickets 5 and 6 with a merged PR and a thread at rest; ticket 5 is a
# sub-issue of $repo#100
merged_fixture() {
  rm -f "$led" "$SA_FAKE/calls"
  for n in 5 6; do
    L add --repo $repo --number $n --thread "t-$n" --worktree "/wt/$n" --branch "feat/x-$n" >/dev/null
    sa_thread "t-$n" idle 2 0 "/wt/$n" "feat/x-$n"
    sa_pr $repo "feat/x-$n" merged
    sa_issue $repo "$n" closed
  done
}
child() { # <state> [<parent url>]: ticket 5's issue JSON
  sa_route "repos/$repo/issues/5" "$(jq -cn --arg s "$1" --arg p "${2-https://api.github.com/repos/$repo/issues/100}" \
    '{number: 5, state: $s, labels: []} + (if $p == "" then {} else {parent_issue_url: $p} end)')"
}
parent() { # <state> <total> <completed>
  sa_route "repos/$repo/issues/100" "$(jq -cn --arg s "$1" --argjson t "$2" --argjson c "$3" \
    '{number: 100, title: "spec: the batch", state: $s, sub_issues_summary: {total: $t, completed: $c, percent_completed: 0}}')"
}
pd() { jq -c '[.parents_done[] | [.key, .title, .sub_issues]]' <<<"$out"; }
checked() { jq -r --arg k "$repo#5" '.entries[$k].parent_checked' "$led"; }

# --- the contract: the field is in the stdout line -----------------------------
check "reconcile --help names parents_done" 1 "$(bash "$s/reconcile.sh" --help | sed -n 2,3p | grep -c parents_done)"

merged_fixture; child closed; parent open 3 3
out=$(R)
check "a merged ticket whose parent has every sub-issue closed offers the parent" "[[\"$repo#100\",\"spec: the batch\",3]]" "$(pd)"
check "the ledger remembers the offer and the look" "[\"$repo#100\"] true" \
  "$(jq -r --arg k "$repo#5" '[(.parents_offered | tojson), (.entries[$k].parent_checked | tostring)] | join(" ")' "$led")"
out=$(R)
check "the next reconcile offers nothing" "[]" "$(pd)"

merged_fixture; child closed; parent open 3 2
out=$(R)
check "a parent with a sub-issue still open is not offered" "[]" "$(pd)"
check "but the look is done" true "$(checked)"
: > "$SA_FAKE/calls"; parent open 3 3
out=$(R)
check "and is not taken again for that ticket" "[] 0" "$(pd) $(calls | grep -c 'issues/100')"

merged_fixture; child closed; parent closed 3 3
out=$(R)
check "a closed parent is not offered" "[]" "$(pd)"

merged_fixture; child closed ""
out=$(R)
check "a ticket with no parent offers nothing" "[] true" "$(pd) $(checked)"

merged_fixture; child open; parent open 1 1
out=$(R)
check "a ticket that does not read closed yet waits for a later wake" "[] null" "$(pd) $(checked)"
child closed
out=$(R)
check "and the parent is offered when it does" "[\"$repo#100\"]" "$(jq -c '[.parents_done[].key]' <<<"$out")"

merged_fixture; child closed; parent open 1 1; sa_gh_fail issues/100 1
out=$(R)
check "an unreadable parent is an issue-unreadable error, not an offer" "[] issue-unreadable $repo#100" "$(pd) $(jq -r '.errors[] | "\(.kind) \(.detail.key)"' <<<"$out")"
out=$(R)
check "and the look is retried" "[\"$repo#100\"]" "$(jq -c '[.parents_done[].key]' <<<"$out")"

# two sub-issues merged under one parent: one offer
merged_fixture; child closed; parent open 2 2
sa_route "repos/$repo/issues/6" "$(jq -cn --arg p "https://api.github.com/repos/$repo/issues/100" '{number: 6, state: "closed", labels: [], parent_issue_url: $p}')"
out=$(R)
check "two merged sub-issues of one parent offer it once" 1 "$(jq '.parents_done | length' <<<"$out")"

finish
