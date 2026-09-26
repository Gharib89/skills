#!/usr/bin/env bash
# The upstream heads `plan` takes: for each GitHub-installed skill in a
# checkout's lock that the source repo does not own, the commit a refresh
# would move it to.
#
#   heads <checkout>
#
# A skill's base is its pin on the checkout's composes lines (ship's and
# setup-skills'), else the lock's recorded ref. Its head is the upstream
# default branch's HEAD when it has no base or its folder changed between the
# base and HEAD, and the base itself otherwise: an upstream commit that touches
# only other skills' folders is no drift, and a repo-level comparison would
# report every skill in a busy upstream as drifted on every run.
#
# Read through GitHub's public REST API with curl rather than `gh`, so a
# checkout whose host is Azure DevOps, with no GitHub credentials, still gets
# heads; GH_TOKEN or GITHUB_TOKEN, where set, only raises the rate limit.
#
# stdout: {"<skill>": "<sha>"}
# exit: 0 · 1 an unreadable lock or a failed request · 2 usage
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../ship/scripts/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: heads <checkout>'
ship_help "$usage" "$@"
[ -n "${1:-}" ] && [ $# -eq 1 ] || ship_tooling "$usage"
root=$1
case $root in -*) ship_tooling "$usage" ;; esac
command -v curl >/dev/null || ship_tooling "curl not installed"

lock=$(jq -ce 'select(type == "object")' "$root/skills-lock.json" 2>/dev/null) || ship_fail "cannot read lock: $root/skills-lock.json"
composes=""
for s in ship setup-skills; do
  [ -f "$root/.claude/skills/$s/SKILL.md" ] && composes="$composes $(ship_frontmatter "$root/.claude/skills/$s/SKILL.md" composes)"
done
token=${GH_TOKEN:-${GITHUB_TOKEN:-}}

api=https://api.github.com
# get <path>: one GET, the body in $body. Not a command substitution of its
# own, so the failure's ship_fail exits the mechanic rather than a subshell.
get() {
  body=$(curl -fsSL -H 'Accept: application/vnd.github+json' ${token:+-H "Authorization: Bearer $token"} "$api/$1" 2>/dev/null) \
    || ship_fail "cannot read $api/$1"
}

# One `<skill>\t<source>\t<folder>\t<base>` row per skill to look up.
rows=$(jq -r --arg composes "$composes" '
  ($composes | split(" ") | map(select(length > 0) | {key: sub("^.*:"; ""), value: (sub(":[^:]*$"; "") | split("#")[1])}) | from_entries) as $pins
  | .skills | to_entries | sort_by(.key)[]
  | select(.value.sourceType == "github" and (.value.source | ascii_downcase) != "gharib89/skills")
  | [.key, .value.source, ((.value.skillPath // "") | sub("/?SKILL\\.md$"; "")), ($pins[.key] // .value.ref // "")] | @tsv' <<<"$lock")

out='{}' seen='{}'
while IFS=$'\t' read -r skill src dir base; do
  [ -n "$skill" ] || continue
  head=$(jq -r --arg s "$src" '.[$s] // ""' <<<"$seen")
  if [ -z "$head" ]; then
    get "repos/$src/commits/HEAD"; head=$(jq -r '.sha // ""' <<<"$body")
    [ -n "$head" ] || ship_fail "no sha in $api/repos/$src/commits/HEAD"
    seen=$(jq -c --arg s "$src" --arg h "$head" '.[$s] = $h' <<<"$seen")
  fi
  at=$head
  if [ -n "$base" ]; then
    at=$base
    if [ "$base" != "$head" ]; then
      get "repos/$src/compare/$base...$head"
      [ "$(jq -r --arg d "${dir:+$dir/}" 'any(.files[]?.filename; startswith($d))' <<<"$body")" = true ] && at=$head
    fi
  fi
  out=$(jq -c --arg k "$skill" --arg v "$at" '.[$k] = $v' <<<"$out")
done <<<"$rows"
printf '%s\n' "$out"
