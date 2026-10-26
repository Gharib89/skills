#!/usr/bin/env bash
# Read the git host's record of a window of merged PRs for a retro run.
#
#   retro candidates [--days <n>]
#
# `candidates` lists the PRs merged in the last <n> days (7 by default) that
# carry a signal, and the class lines of every earlier issue labelled `retro`,
# open or closed. A signal is one of: a review thread opened by anyone but the
# PR's author (`thread`); a `## Special things to note` bullet, the Door line
# aside, naming a deviation or departure (`deviation`), since Ship folds its
# deviations log into that section; a `## Needs attention` section other than
# `None.` (`needs-attention`); a `## Review` section recording a second round
# (`review-rounds`). A class line is a body line `Class: <key>`. Reads the
# repository of the current directory (or GH_REPO) over REST only, since a
# cloud sandbox refuses GraphQL, and writes nothing.
#
# stdout: {since, merged, candidates[], filed[]}: `since` the window's start
#         (UTC), `merged` the count of PRs merged in it; each candidate
#         {number, title, url, closes[], signals[]} lowest number first,
#         `closes` the issues its body closes, each signal {kind, text}, a
#         `thread` also {author, path, replies[]}, each reply {author, text};
#         each filed issue {number, state, classes[]}
# exit: 0 answered · 1 GitHub refused a read (gh's message in `error`) · 2
#       usage, gh or jq missing, or an answer from gh it cannot read
set -uo pipefail

usage='usage: retro candidates [--days <n>]'
tooling() { jq -cn --arg e "$1" '{error: $e}'; printf '%s\n' "$1" >&2; exit 2; }
fail() { jq -cn --arg e "$1" '{error: $e}'; printf '%s\n' "$1" >&2; exit 1; }

if [ "${1:-}" = --help ]; then
  printf '%s\n' "$usage"
  awk '/^# stdout:/ { f = 1 }
    f { if ($0 !~ /^#/ || /^# exit:/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
  exit 0
fi
# tooling's answer, written by hand because tooling itself needs jq.
command -v jq >/dev/null || { printf '{"error":"jq not installed"}\n'; echo "jq not installed" >&2; exit 2; }
[ "${1:-}" = candidates ] || tooling "$usage"
shift
days=7
while [ $# -gt 0 ]; do
  case $1 in
    --days) [[ ${2:-} =~ ^[1-9][0-9]*$ ]] || tooling "$usage"; days=$2; shift 2 ;;
    *) tooling "$usage" ;;
  esac
done
command -v gh >/dev/null || tooling "gh not installed"

# get <what> <endpoint>: every page of a REST read, in $got. Run in this shell,
# not a command substitution, so a refusal exits.
get() {
  got=$(gh api --paginate "$2" 2>&1 </dev/null) || fail "$1: $(tail -1 <<<"$got")"
}

get "the repository" 'repos/{owner}/{repo}'
repo=$(jq -er '.full_name | strings' <<<"$got" 2>/dev/null) || tooling "the repository: unreadable answer from gh"
since=$(jq -nr --argjson d "$days" 'now - $d * 86400 | todate')
# Search filters by day; the merged_at comparison makes the window exact.
get "merged PRs" "search/issues?q=repo:$repo+is:pr+is:merged+merged:>=${since%%T*}&per_page=100"
prs=$(jq -cs --arg since "$since" '
  if length == 0 then error else . end
  | [.[].items[] | select(.pull_request.merged_at >= $since)
    | {number, title, url: .html_url, author: .user.login, body: (.body // "" | gsub("\r"; ""))}]
  | if all(.[]; (.number | type) == "number" and (.title | type) == "string" and (.author | type) == "string")
    then sort_by(.number) else error end' <<<"$got" 2>/dev/null) \
  || tooling "merged PRs: unreadable answer from gh"

# One PR as a candidate, given {pr, comments}, or nothing when it carries no signal.
candidate='def section($h): [.pr.body | scan("(?ms)^## " + $h + "[ \t]*\n(.*?)(?=^## |\\z)")] | (.[0][0] // "") | gsub("^\\s+|\\s+$"; "");
  .comments as $c
  | ([$c[] | select(.in_reply_to_id == null and .user.login != $author) | .id as $id
    | {kind: "thread", author: .user.login, path, text: .body,
       replies: [$c[] | select(.in_reply_to_id == $id) | {author: .user.login, text: .body}]}]
  + [section("Special things to note") | ("\n" + .) | split("\n- ")[1:][] | "- " + gsub("\\s+$"; "")
    | select((test("^- \\S+ Door:") | not) and test("(?i)deviat|departure")) | {kind: "deviation", text: .}]
  + [section("Needs attention") | select(. != "" and . != "None.") | {kind: "needs-attention", text: .}]
  + [section("Review") | select(test("(?i)\\bround [2-9]\\b|\\b([2-9]|two|three) (host |local )?rounds\\b"))
    | {kind: "review-rounds", text: .}]) as $s
  | if ($s | length) == 0 then empty else
    {number: .pr.number, title: .pr.title, url: .pr.url,
     closes: [.pr.body | scan("(?i)\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?) #([0-9]+)") | .[0] | tonumber],
     signals: $s} end'
found=''
while read -r pr; do
  n=$(jq -r .number <<<"$pr")
  get "review comments of #$n" "repos/{owner}/{repo}/pulls/$n/comments?per_page=100"
  line=$(jq -cs --argjson pr "$pr" --arg author "$(jq -r .author <<<"$pr")" \
    "{pr: \$pr, comments: add} | $candidate" <<<"$got" 2>/dev/null) \
    || tooling "review comments of #$n: unreadable answer from gh"
  found="$found$line"$'\n'
done < <(jq -c '.[]' <<<"$prs")

get "earlier retro issues" 'repos/{owner}/{repo}/issues?labels=retro&state=all&per_page=100'
filed=$(jq -cs '[add[] | select(has("pull_request") | not)
  | {number, state, classes: [.body // "" | scan("(?m)^Class: *(.+?)[ \r]*$") | .[0]]}] | sort_by(.number)' <<<"$got" 2>/dev/null) \
  || tooling "earlier retro issues: unreadable answer from gh"

jq -cs --arg since "$since" --argjson merged "$(jq length <<<"$prs")" --argjson filed "$filed" \
  '{since: $since, merged: $merged, candidates: ., filed: $filed}' <<<"$found"
