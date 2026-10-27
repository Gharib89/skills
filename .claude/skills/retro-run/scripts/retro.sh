#!/usr/bin/env bash
# Read the git host's record of a window of merged PRs for a retro run, and
# file the classes of mistake the run finds recurring in it.
#
#   retro candidates [--days <n>]
#   retro file <findings.json>
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
# cloud sandbox refuses GraphQL; `candidates` writes nothing.
#
# `file` files the model's findings, a JSON array of {key, summary, prs[], site}
# (`key` kebab-case and unique, `prs` the PR numbers it was seen in, `site` the
# proposed fix site, `summary` and `site` one line each), as one issue labelled
# `needs-triage` and `retro`, creating the `retro` label when missing. It first
# drops each finding whose key an earlier `retro` issue lists, and files nothing
# when none is left or the file is empty or `[]`. The body carries each key as
# a `Class: <key>` line, so `candidates` reads it back. REST only, like
# `candidates`.
#
# stdout: candidates: {since, merged, candidates[], filed[]}: `since` the
#         window's start (UTC), `merged` the count of PRs merged in it; each
#         candidate {number, title, url, closes[], signals[]} lowest number
#         first, `closes` the issues its body closes, each signal {kind,
#         text}, a `thread` also {author, path, replies[]}, each reply
#         {author, text}; each filed issue {number, state, classes[]}
#         file: {issue, url, filed[], dropped[]}: the issue created, or both
#         null when nothing was left to file; `filed` and `dropped` class keys
# exit: 0 answered · 1 GitHub refused a read or a write (gh's message in
#       `error`) · 2 usage, a findings file it cannot read, gh or jq missing,
#       or an answer from gh it cannot read
set -uo pipefail

usage='usage: retro candidates [--days <n>] | retro file <findings.json>'
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
cmd=${1:-}
case $cmd in
  candidates)
    shift
    days=7
    while [ $# -gt 0 ]; do
      case $1 in
        --days) [[ ${2:-} =~ ^[1-9][0-9]*$ ]] || tooling "$usage"; days=$2; shift 2 ;;
        *) tooling "$usage" ;;
      esac
    done ;;
  file)
    [ $# -eq 2 ] || tooling "$usage"
    [ -f "$2" ] && [ -r "$2" ] || tooling "findings: cannot read $2"
    # One line per summary and site, so no body line but the script's own
    # reads as a `Class:` line.
    findings=$(jq -cs --arg f "$2" 'def line: type == "string" and . != "" and (test("[\r\n]") | not);
      def entry: type == "object" and (.key | type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$"))
        and (.summary | line) and (.site | line)
        and (.prs | type == "array" and length > 0 and all(.[]; type == "number"));
      (if length == 0 then [] elif length == 1 then .[0] else null end) as $a
      | if ($a | type) != "array" then {error: "findings \($f): not a JSON array"}
        else first(($a | to_entries[] | select(.value | entry | not)
            | {error: "findings \($f): entry [\(.key)] is not {key, summary, prs[], site}"}),
          ($a | group_by(.key)[] | select(length > 1)
            | {error: "findings \($f): key \(.[0].key) appears twice"}),
          {findings: $a}) end' "$2" 2>/dev/null) || tooling "findings $2: not JSON"
    jq -e 'has("findings")' <<<"$findings" >/dev/null || tooling "$(jq -r .error <<<"$findings")"
    findings=$(jq -c .findings <<<"$findings") ;;
  *) tooling "$usage" ;;
esac
command -v gh >/dev/null || tooling "gh not installed"

# get <what> <endpoint>: every page of a REST read, in $got. Run in this shell,
# not a command substitution, so a refusal exits.
get() {
  got=$(gh api --paginate "$2" 2>&1 </dev/null) || fail "$1: $(tail -1 <<<"$got")"
}

# read_filed: every earlier issue labelled `retro`, with its class lines, in $filed.
read_filed() {
  get "earlier retro issues" 'repos/{owner}/{repo}/issues?labels=retro&state=all&per_page=100'
  filed=$(jq -cs '[add[] | select(has("pull_request") | not)
    | {number, state, classes: [.body // "" | scan("(?m)^Class: *(.+?)[ \r]*$") | .[0]]}] | sort_by(.number)' <<<"$got" 2>/dev/null) \
    || tooling "earlier retro issues: unreadable answer from gh"
}

if [ "$cmd" = file ]; then
  read_filed
  split=$(jq -c --argjson filed "$filed" 'map(. + {old: (.key | IN($filed[].classes[]))})
    | {kept: map(select(.old | not) | del(.old)), dropped: map(select(.old) | .key)}' <<<"$findings")
  if jq -e '.kept == []' <<<"$split" >/dev/null; then
    jq -c '{issue: null, url: null, filed: [], dropped}' <<<"$split"
    exit 0
  fi
  # A missing label answers 404; anything else is a refusal.
  if ! got=$(gh api 'repos/{owner}/{repo}/labels/retro' 2>&1 </dev/null); then
    [[ $got == *"(HTTP 404)"* ]] || fail "the retro label: $(tail -1 <<<"$got")"
    got=$(jq -cn '{name: "retro", color: "c5def5", description: "Filed by a retro run: classes of mistake that recurred across merged PRs"}' \
      | gh api -X POST 'repos/{owner}/{repo}/labels' --input - 2>&1) || fail "creating the retro label: $(tail -1 <<<"$got")"
  fi
  got=$(jq -c --arg date "$(date -u +%F)" '.kept | {
    title: "Retro run \($date): \(length) recurring \(if length == 1 then "class" else "classes" end) of mistake",
    labels: ["needs-triage", "retro"],
    body: ("A retro run found these classes of mistake recurring across two or more merged PRs, none listed by an earlier `retro` issue. Triage each: accept it as a ticket at its proposed fix site, or decline it. Later retro runs leave out every class listed here either way.\n\n## Findings\n"
      + (map("\n### \(.key)\n\nClass: \(.key)\nSeen in: \(.prs | map("#\(.)") | join(", "))\nProposed fix site: \(.site)\nSummary: \(.summary)\n") | join("")))}' <<<"$split" \
    | gh api -X POST 'repos/{owner}/{repo}/issues' --input - 2>&1) || fail "creating the issue: $(tail -1 <<<"$got")"
  jq -ec --argjson split "$split" '{issue: (.number | numbers), url: (.html_url | strings),
    filed: [$split.kept[].key], dropped: $split.dropped}' <<<"$got" 2>/dev/null \
    || tooling "creating the issue: unreadable answer from gh"
  exit 0
fi

since=$(jq -nr --argjson d "$days" 'now - $d * 86400 | todate')
# The closed pulls, last updated first, a page at a time: a cloud session's
# proxy answers 403 to any path outside repos/{owner}/{repo}/, search included
# (#988). A PR is never updated before it merged, so the first page reaching
# back past the window start is the last one that can hold a PR merged inside
# it. Not `get`'s --paginate, which would read every closed PR the repo has.
pages='' page=1
while :; do
  got=$(gh api "repos/{owner}/{repo}/pulls?state=closed&sort=updated&direction=desc&per_page=100&page=$page" 2>&1 </dev/null) \
    || fail "merged PRs: $(tail -1 <<<"$got")"
  more=$(jq --arg since "$since" 'if type == "array" then length == 100 and all(.[]; .updated_at >= $since) else error end' \
    <<<"$got" 2>/dev/null)
  [ -n "$more" ] || tooling "merged PRs: unreadable answer from gh"
  pages+=$got$'\n'
  [ "$more" = true ] || break
  page=$((page + 1))
done
# jq orders null below every string, so the merged_at comparison drops an unmerged PR.
prs=$(jq -cs --arg since "$since" '
  [add[] | select(.merged_at >= $since)
    | {number, title, url: .html_url, author: .user.login, body: (.body // "" | gsub("\r"; ""))}]
  | if all(.[]; (.number | type) == "number" and (.title | type) == "string" and (.author | type) == "string")
    then sort_by(.number) else error end' <<<"$pages" 2>/dev/null) \
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
  + [section("Review") | select(test("(?i)\\bround [2-9]\\b|\\b([2-9]|two|three|four|five|six|seven|eight|nine) (host |local )?rounds\\b"))
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

read_filed

jq -cs --arg since "$since" --argjson merged "$(jq length <<<"$prs")" --argjson filed "$filed" \
  '{since: $since, merged: $merged, candidates: ., filed: $filed}' <<<"$found"
