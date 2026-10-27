#!/usr/bin/env bash
# retro-run's `retro.sh candidates`: the merged PRs of a window that carry a
# signal, and the class lines of earlier `retro` issues, read over REST from a
# fake `gh` answering per endpoint.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/gh-fake.sh

s=skills/retro-run/scripts/retro.sh
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
gh_fake_install "$tmp/bin"
export GH_ROUTES=$tmp/routes
gh_reset

# ago <days>: a timestamp that many days before now.
ago() { jq -nr --argjson d "$1" 'now - $d * 86400 | todate'; }
# pr <number> <days ago> <body>: one closed PR of the pulls list, authored by
# `owner`, created, updated and merged that many days ago.
pr() {
  jq -cn --argjson n "$1" --arg m "$(ago "$2")" --arg b "$3" '{number: $n, title: "PR \($n)",
    html_url: "https://github.com/o/r/pull/\($n)", user: {login: "owner"}, body: $b,
    created_at: $m, updated_at: $m, merged_at: $m}'
}
pulls='repos/{owner}/{repo}/pulls'
door='## Special things to note

- 🟢 Door: two-way. Blast radius: none.'
clean="Closes #1

$door

## Needs attention

None.

## Review

- codex: reviewed. One round, clean."

items=$(jq -cs . <<EOF
$(pr 10 1 "$clean")
$(pr 11 1 "$clean")
$(pr 12 1 "${clean/Blast radius: none./Blast radius: none.
- Deviation: the brief named a file that had moved.}")
$(pr 13 1 "${clean/None./- Ship note: poll-pr read a stale head.}")
$(pr 14 1 "${clean/One round, clean./Round 1 raised one P2, fixed; round 2 was clean.}")
$(pr 15 10 "${clean/One round, clean./Round 1 raised one P2, fixed; round 2 was clean.}")
$(pr 16 1 "$clean")
$(pr 17 6.99 "${clean/One round, clean./Round 1 raised one P2, fixed; round 2 was clean.}")
$(pr 18 7.01 "${clean/One round, clean./Round 1 raised one P2, fixed; round 2 was clean.}")
$(pr 19 1 "## Why the change

A deviation from the brief, and round 2 of the review, told in the wrong section.

${clean#Closes #1

}")
$(pr 20 1 "${clean/Closes #1/This fixes #4.}
- claude: two rounds.")
$(pr 22 1 "${clean/Blast radius: none./Blast radius: none; a departure from the brief.}")
$(pr 23 1 "${clean/One round, clean./Four rounds, each with findings.}")
$(pr 24 1 "${clean/One round, clean./Round 1 raised one P2, fixed; round 2 was clean.}" | jq -c '.merged_at = null')
$(pr 25 1 "${clean/One round, clean./Round 1 raised one P2, fixed; round 2 was clean.}" | jq -c --arg c "$(ago 30)" '.created_at = $c')
EOF
)
gh_route "$pulls" "$items"
for n in 10 12 13 14 15 17 18 19 20 22 23 24 25; do gh_route "repos/{owner}/{repo}/pulls/$n/comments" '[]'; done
# #11 carries one thread a reviewer opened; #16 only the author's own comment.
gh_route 'repos/{owner}/{repo}/pulls/11/comments' '[
  {"id": 1, "in_reply_to_id": null, "user": {"login": "codex[bot]"}, "path": "a.sh", "body": "P2: the read is never paged"},
  {"id": 2, "in_reply_to_id": 1, "user": {"login": "owner"}, "path": "a.sh", "body": "Fixed."}]'
gh_route 'repos/{owner}/{repo}/pulls/16/comments' '[
  {"id": 3, "in_reply_to_id": null, "user": {"login": "owner"}, "path": "b.sh", "body": "a note to self"}]'
gh_route 'repos/{owner}/{repo}/issues' '[
  {"number": 900, "state": "closed", "body": "## Findings\n\nClass: unpaged-list-read\nPRs: #1, #2\n\nClass: stale-head\n"},
  {"number": 901, "state": "open", "body": "Class: brief-path-moved\r\n"},
  {"number": 902, "state": "closed", "body": null, "pull_request": {}}]'

out=$(bash "$s" candidates); rc=$?
check_rc "candidates answers" 0 "$rc"
check "only the signal PRs in the window, its edge included, lowest first" '[11,12,13,14,17,20,23,25]' \
  "$(jq -c '[.candidates[].number]' <<<"$out")"
check "a reviewer's thread is the signal, its replies carried with it" \
  '[{"kind":"thread","author":"codex[bot]","path":"a.sh","text":"P2: the read is never paged","replies":[{"author":"owner","text":"Fixed."}]}]' \
  "$(jq -c '.candidates[] | select(.number == 11) | .signals' <<<"$out")"
check "a deviation bullet, the Door line aside" '[{"kind":"deviation","text":"- Deviation: the brief named a file that had moved."}]' \
  "$(jq -c '.candidates[] | select(.number == 12) | .signals' <<<"$out")"
check "a Needs attention section other than None." '[{"kind":"needs-attention","text":"- Ship note: poll-pr read a stale head."}]' \
  "$(jq -c '.candidates[] | select(.number == 13) | .signals' <<<"$out")"
check "a Review section recording a second round" '["review-rounds"]' \
  "$(jq -c '[.candidates[] | select(.number == 14) | .signals[].kind]' <<<"$out")"
check "a round count in words past three" '["review-rounds"]' \
  "$(jq -c '[.candidates[] | select(.number == 23) | .signals[].kind]' <<<"$out")"
check "a Door line naming a departure is no deviation" '' "$(jq '.candidates[] | select(.number == 22)' <<<"$out")"
check "each candidate names its title, url and closing issue" '{"title":"PR 12","url":"https://github.com/o/r/pull/12","closes":[1]}' \
  "$(jq -c '.candidates[] | select(.number == 12) | {title, url, closes}' <<<"$out")"
check "another closing keyword, in any case" '[4]' "$(jq -c '.candidates[] | select(.number == 20) | .closes' <<<"$out")"
check "merged counts every PR merged in the window, the closed unmerged one aside" 12 "$(jq .merged <<<"$out")"
check "earlier retro issues' class lines, pull requests aside" \
  '[{"number":900,"state":"closed","classes":["unpaged-list-read","stale-head"]},{"number":901,"state":"open","classes":["brief-path-moved"]}]' \
  "$(jq -c .filed <<<"$out")"
check "no GraphQL call" '' "$(gh_args | grep -F graphql)"
check "every call is repository-scoped" '' "$(gh_args | awk '{print $NF}' | grep -v '^repos/{owner}/{repo}/')"
check "the pulls list is read newest update first, one page at a time" \
  "$pulls?state=closed&sort=updated&direction=desc&per_page=100&page=1" \
  "$(gh_args | grep -F "$pulls?" | awk '{print $NF}')"
check "never through --paginate, which reads every page" '' "$(gh_args | grep -F "$pulls?" | grep -F -- --paginate)"

out=$(bash "$s" candidates --days 14)
check "--days widens the window" '[11,12,13,14,15,17,18,20,23,25]' "$(jq -c '[.candidates[].number]' <<<"$out")"
check "since is the window's start" true "$(jq --arg a "$(ago 14.01)" --arg b "$(ago 13.99)" '.since > $a and .since < $b' <<<"$out")"

for bad in '--days 0' '--days -1' '--days' 'other'; do
  # shellcheck disable=SC2086 # each case is a word list
  out=$(bash "$s" $bad 2>/dev/null); rc=$?
  check_rc "a malformed call exits 2: $bad" 2 "$rc"
  check "with its usage line: $bad" 'usage: retro candidates [--days <n>] | retro file <findings.json>' "$(jq -r .error <<<"$out")"
done

mkdir -p "$tmp/nogh"
ln -s "$(command -v jq)" "$tmp/nogh/jq"
out=$(PATH=$tmp/nogh /bin/bash "$s" candidates 2>/dev/null); rc=$?
check_rc "gh missing exits 2" 2 "$rc"
check "and says so" 'gh not installed' "$(jq -r .error <<<"$out")"

gh_route "$pulls" "[$(pr 21 1 "$clean" | jq -c '.title = null')]"
out=$(bash "$s" candidates 2>/dev/null); rc=$?
check_rc "an item it cannot read exits 2" 2 "$rc"
check "naming the read" 'merged PRs: unreadable answer from gh' "$(jq -r .error <<<"$out")"

out=$(PATH=$tmp/bin /bin/bash "$s" candidates 2>/dev/null); rc=$?
check_rc "jq missing exits 2" 2 "$rc"
check "and says so in JSON written without it" 'jq not installed' "$(jq -r .error <<<"$out")"

# An empty answer is unreadable, never an empty window.
gh_route "$pulls" ''
out=$(bash "$s" candidates 2>/dev/null); rc=$?
check_rc "an empty pulls answer exits 2" 2 "$rc"
check "naming the read" 'merged PRs: unreadable answer from gh' "$(jq -r .error <<<"$out")"

gh_route "$pulls" "$items"
for read in 'review comments of #14:repos/{owner}/{repo}/pulls/14/comments' 'earlier retro issues:repos/{owner}/{repo}/issues'; do
  what=${read%%:*} endpoint=${read#*:}
  saved=$(cat "$GH_ROUTES/${endpoint//\//_}")
  gh_route "$endpoint" ''
  out=$(bash "$s" candidates 2>/dev/null); rc=$?
  check_rc "an empty answer exits 2: $what" 2 "$rc"
  check "naming the read: $what" "$what: unreadable answer from gh" "$(jq -r .error <<<"$out")"
  gh_route "$endpoint" "$saved"
done

rm "$GH_ROUTES/repos_{owner}_{repo}_pulls_14_comments"
out=$(bash "$s" candidates 2>/dev/null); rc=$?
check_rc "a refused read exits 1" 1 "$rc"
check "naming the read" 'review comments of #14: gh: Not Found (HTTP 404)' "$(jq -r .error <<<"$out")"

rm "$GH_ROUTES/${pulls//\//_}"
out=$(bash "$s" candidates 2>/dev/null); rc=$?
check_rc "a refused pulls page exits 1" 1 "$rc"
check "naming the read" 'merged PRs: gh: Not Found (HTTP 404)' "$(jq -r .error <<<"$out")"

# A full first page: PR 100 merged in the window, 99 closed unmerged ones updated
# in it. The query-less route answers every later page: PR 31 merged in the window.
page1="$pulls?state=closed&sort=updated&direction=desc&per_page=100&page=1"
full=$(jq -cn --arg r "$(ago 1)" '[range(100) as $i | {number: (100 + $i), title: "PR \(100 + $i)",
  html_url: "https://github.com/o/r/pull/\(100 + $i)", user: {login: "owner"}, body: "",
  created_at: $r, updated_at: $r, merged_at: (if $i == 0 then $r else null end)}]')
gh_route 'repos/{owner}/{repo}/pulls/100/comments' '[]'
gh_route 'repos/{owner}/{repo}/pulls/31/comments' '[]'
gh_route "$pulls" "[$(pr 31 2 "${clean/One round, clean./Round 1 raised one P2, fixed; round 2 was clean.}")]"
gh_route "$page1" "$full"
gh_reset
out=$(bash "$s" candidates); rc=$?
check_rc "a full page in the window reads the next" 0 "$rc"
check "two pages read" 2 "$(gh_args | grep -cF "$pulls?")"
check "the next page's PRs kept" '{"merged":2,"candidates":[31]}' "$(jq -c '{merged, candidates: [.candidates[].number]}' <<<"$out")"

gh_route "$page1" "$(jq -c --arg o "$(ago 8)" '.[99].updated_at = $o' <<<"$full")"
gh_reset
out=$(bash "$s" candidates); rc=$?
check_rc "a full page reaching past the window answers" 0 "$rc"
check "and is the last page read" 1 "$(gh_args | grep -cF "$pulls?")"
check "so the next page's PRs are never read" '{"merged":1,"candidates":[]}' "$(jq -c '{merged, candidates: [.candidates[].number]}' <<<"$out")"

gh_route "$page1" "$full"
gh_route "$pulls" ''
out=$(bash "$s" candidates 2>/dev/null); rc=$?
check_rc "an empty later page exits 2" 2 "$rc"
check "naming the read" 'merged PRs: unreadable answer from gh' "$(jq -r .error <<<"$out")"

rm "$GH_ROUTES/${pulls//\//_}"
out=$(bash "$s" candidates 2>/dev/null); rc=$?
check_rc "a refused later page exits 1" 1 "$rc"
check "naming the read" 'merged PRs: gh: Not Found (HTTP 404)' "$(jq -r .error <<<"$out")"

finish
