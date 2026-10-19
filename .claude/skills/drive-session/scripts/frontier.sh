#!/usr/bin/env bash
# Print a spec parent's sub-issues with the blockers each still waits on.
#
#   frontier --parent <n>
#
# Reads the repository of the current directory (or GH_REPO) over REST, never
# GraphQL, which flakes mid-session: the parent's sub-issues, then the blocked-by
# edges of each open one, from that sub-issue's own repo. A blocker is `inside`
# when it is one of the parent's own sub-issues, so it clears as the batch
# merges; one outside the spec does not. It reads GitHub alone, so it takes no
# roster and runs outside Herdr.
#
# stdout: {parent, sub_issues[]}, each sub-issue {number, title, repo, state,
#         assignees[], blockers[]} lowest number first, `assignees` its logins,
#         each open blocker {number, title, repo, inside}, each `repo` an
#         `owner/name`; a closed sub-issue's blockers are not read and list none
# exit: 0 answered · 1 GitHub refused a read (gh's message in `error`) · 2
#       usage, gh missing, or an answer from gh it cannot read
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: frontier --parent <n>'
ds_help "$usage" "$@"
[ "${1:-}" = --parent ] && [[ ${2:-} =~ ^[1-9][0-9]*$ ]] && [ $# -eq 2 ] || ds_tooling "$usage"
parent=$2
command -v gh >/dev/null || ds_tooling "gh not installed"

# list <what> <endpoint>: every page of a list endpoint as one JSON array, in
# $listed, cut to the fields read: a whole issue body can pass jq's per-argument
# limit (128 KiB) as --argjson. Run in this shell, not a command substitution, so a refusal exits.
list() {
  local out
  out=$(gh api --paginate "$2?per_page=100" 2>&1 </dev/null) \
    || ds_fail "$1: $(tail -1 <<<"$out")"
  listed=$(jq -ces 'def issue: type == "object" and (.number | type) == "number"
      and (.title | type) == "string" and (.state | type) == "string"
      and (.repository_url | type) == "string" and (.assignees | type) == "array"
      and all(.assignees[]; (.login | type) == "string");
    if length > 0 and all(type == "array" and all(.[]; issue)) then
      add | map({number, title, state, repository_url, assignees: [.assignees[] | {login}]}) else error end' <<<"$out" 2>/dev/null) \
    || ds_tooling "$1: unreadable answer from gh"
}

list "sub-issues of #$parent" "repos/{owner}/{repo}/issues/$parent/sub_issues"
subs=$listed
result='[]'
# A sub-issue may live in another repo, under a number this one also uses: its
# blockers are read from its own repo.
while read -r sub; do
  repo=$(jq -r '.repository_url | sub("^.*/repos/"; "")' <<<"$sub")
  n=$(jq -r .number <<<"$sub")
  blockers='[]'
  if [ "$(jq -r .state <<<"$sub")" = open ]; then
    list "blockers of $repo#$n" "repos/$repo/issues/$n/dependencies/blocked_by"
    blockers=$listed
  fi
  result=$(jq -c --argjson s "$sub" --arg repo "$repo" --argjson b "$blockers" --argjson all "$subs" '. + [{
    number: $s.number, title: $s.title, repo: $repo, state: $s.state, assignees: [$s.assignees[].login],
    blockers: [$b[] | select(.state == "open") as $x
      | {number: $x.number, title: $x.title, repo: ($x.repository_url | sub("^.*/repos/"; "")),
         inside: any($all[]; .number == $x.number and .repository_url == $x.repository_url)}]}]' <<<"$result")
done < <(jq -c 'sort_by(.number, .repository_url)[]' <<<"$subs")
jq -cn --argjson p "$parent" --argjson s "$result" '{parent: $p, sub_issues: $s}'
