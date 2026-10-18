#!/usr/bin/env bash
# Print a spec parent's sub-issues with the blockers each still waits on.
#
#   frontier --parent <n>
#
# Reads the repository of the current directory (or GH_REPO) over REST, never
# GraphQL, which flakes mid-session: the parent's sub-issues, then the blocked-by
# edges of each open one. A blocker is `inside` when it is one of the parent's
# own sub-issues, so it clears as the batch merges; one outside the spec does
# not. It reads GitHub alone, so it takes no roster and runs outside Herdr.
#
# stdout: {parent, sub_issues[]}, each sub-issue {number, title, state,
#         blockers[]} lowest number first, each open blocker {number, title,
#         inside}; a closed sub-issue's blockers are not read and list none
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
# $listed. Run in this shell, not a command substitution, so a refusal exits.
list() {
  local out
  out=$(gh api --paginate "repos/{owner}/{repo}/issues/$2?per_page=100" 2>&1 </dev/null) \
    || ds_fail "$1: $(tail -1 <<<"$out")"
  listed=$(jq -ces 'if length > 0 and all(type == "array") then add else error end' <<<"$out" 2>/dev/null) \
    || ds_tooling "$1: unreadable answer from gh"
}

list "sub-issues of #$parent" "$parent/sub_issues"
subs=$listed
result='[]'
while read -r n; do
  sub=$(jq -c --argjson n "$n" '.[] | select(.number == $n)' <<<"$subs")
  blockers='[]'
  if [ "$(jq -r .state <<<"$sub")" = open ]; then
    list "blockers of #$n" "$n/dependencies/blocked_by"
    blockers=$listed
  fi
  result=$(jq -c --argjson s "$sub" --argjson b "$blockers" --argjson all "$subs" '. + [{
    number: $s.number, title: $s.title, state: $s.state,
    blockers: [$b[] | select(.state == "open") as $x
      | {number: $x.number, title: $x.title,
         inside: any($all[]; .number == $x.number and .repository_url == $x.repository_url)}]}]' <<<"$result")
done < <(jq -r 'map(.number) | sort[]' <<<"$subs")
jq -cn --argjson p "$parent" --argjson s "$result" '{parent: $p, sub_issues: $s}'
