#!/usr/bin/env bash
# Claim a ticket so two super agents on different machines never take the same
# one: post a claim comment naming the machine and the claiming thread. The
# claim is that comment only: the script never assigns the ticket, because
# Ship's preflight stops on any assignee (`already claimed`) and `/ship`
# assigns through its own claim. A claim by another machine is reported with its age
# and never taken over: a claim older than --stale-after is `stale`, which the
# caller offers back to the owner. The claim is a comment whose first line is
# `<!-- super-agent-claim machine=<m> thread=<t> -->`, posted by the signed-in
# account (a claim-shaped comment of anyone else is ignored); the earliest one on the
# issue is the holder's, so two claims posted at once resolve to one: the later
# one deletes its own comment and reports the holder.
#
#   claim --repo <owner/name> --number <n> --machine <key> --thread <id>
#         [--stale-after <seconds>] [--now <iso time>] [--check]
#
# --machine is the fleet key of this machine and --thread the claiming thread
# (the super agent's own, not the supervised thread, which does not exist
# before the launch). A claim by the same machine is ours, so a restarted super
# agent finds its own claims. --stale-after defaults to 259200 (3 days).
# --check reads the claim and writes nothing. --now is the time ages count
# from (the current time when omitted).
#
# stdout: {repo, number, status, claim, stale_after}: `status` one of `taken`
#         (a fresh claim), `own` (already ours), `free`
#         (--check, nobody holds it), `claimed` (another machine holds it),
#         `stale` (another machine's claim older than --stale-after); `claim`
#         {machine, thread, comment_id, created_at, age_s} or null
# exit: 0 `taken`, `own` or `free` · 1 `claimed` or `stale`, the ticket is not
#       ours to take · 2 usage, a comment list, post or delete the
#       host refused, or a posted claim that vanished
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: claim --repo <owner/name> --number <n> --machine <key> --thread <id> [--stale-after <seconds>] [--now <iso time>] [--check]'
sa_help "$usage" "$@"
repo='' number='' machine='' thread='' stale=259200 now='' check=false
while [ $# -gt 0 ]; do
  case $1 in
    --check) check=true; shift; continue ;;
    --repo|--number|--machine|--thread|--stale-after|--now) sa_flag_value "$usage" "${2:-}" ;;
    *) sa_tooling "$usage" ;;
  esac
  case $1 in
    --repo) repo=$2 ;; --machine) machine=$2 ;; --thread) thread=$2 ;;
    --number) case $2 in *[!0-9]*) sa_tooling "$usage" ;; esac; number=$2 ;;
    --stale-after) sa_window_flag "$usage" "$2"; stale=$2 ;;
    --now) now=$2 ;;
  esac
  shift 2
done
[ -n "$repo" ] && [ -n "$number" ] && [ -n "$machine" ] && [ -n "$thread" ] || sa_tooling "$usage"
case $repo in */*/*|*/|/*|*[!A-Za-z0-9._/-]*|'') sa_tooling "$usage" ;; */*) ;; *) sa_tooling "$usage" ;; esac
case $machine$thread in *[[:space:]]*) sa_tooling "machine and thread must not hold spaces" ;; esac
if [ -n "$now" ]; then now_s=$(date -u -d "$now" +%s 2>/dev/null) || sa_tooling "$usage"
else now_s=$(date -u +%s); fi

comments="repos/$repo/issues/$number/comments"

# me: the account the super agents sign in as. Only its comments are claims, so
# a passer-by posting the marker on a public issue blocks nothing.
raw=$(gh api user 2>/dev/null </dev/null) || sa_tooling "cannot read the signed-in account"
me=$(jq -r '.login // empty' <<<"$raw")
[ -n "$me" ] || sa_tooling "cannot read the signed-in account"

# claims: the claim comments of the issue as {machine, thread, comment_id, created_at, age_s},
# earliest first, in $claims.
read_claims() {
  local raw
  raw=$(gh api --paginate "$comments" 2>/dev/null </dev/null) || sa_tooling "cannot read $comments"
  claims=$(jq -sc --argjson now "$now_s" --arg me "$me" '
    (add // []) | map(select(.user.login == $me and (.body | test("^<!-- super-agent-claim machine=[^ ]+ thread=[^ ]+ -->"))))
    | sort_by(.id)
    | map((.body | capture("^<!-- super-agent-claim machine=(?<machine>[^ ]+) thread=(?<thread>[^ ]+) -->"))
        + {comment_id: .id, created_at: .created_at, age_s: ($now - (.created_at | fromdateiso8601))})' <<<"$raw") \
    || sa_tooling "$comments: not a comment list"
}

# answer <status> <claim json> <exit code>
answer() {
  jq -cn --arg r "$repo" --argjson n "$number" --arg s "$1" --argjson c "$2" --argjson st "$stale" \
    '{repo: $r, number: $n, status: $s, claim: $c, stale_after: $st}'
  exit "$3"
}

# held_by_other: answers for a claim of another machine, never returns.
held_by_other() {
  local c=$1
  if [ "$(jq '.age_s > '"$stale" <<<"$c")" = true ]; then answer stale "$c" 1; fi
  answer claimed "$c" 1
}

read_claims
first=$(jq -c '.[0] // null' <<<"$claims")
if [ "$first" != null ]; then
  if [ "$(jq -r .machine <<<"$first")" = "$machine" ]; then
    answer own "$first" 0
  fi
  held_by_other "$first"
fi
$check && answer free null 0

text=$(printf '<!-- super-agent-claim machine=%s thread=%s -->\nClaimed by a super agent on `%s` (thread `%s`). Another super agent skips this ticket; ask the owner before taking it over.' \
  "$machine" "$thread" "$machine" "$thread")
posted=$(gh api -X POST "$comments" -f "body=$text" 2>/dev/null </dev/null) || posted=''
mine=$(jq -r '.id // empty' <<<"$posted" 2>/dev/null)
[ -n "$mine" ] || sa_tooling "cannot post the claim on $comments"

# Two claims posted together both saw none: the earliest comment holds it.
read_claims
first=$(jq -c '.[0] // null' <<<"$claims")
if [ "$first" = null ] || [ "$(jq -r .comment_id <<<"$first")" != "$mine" ]; then
  gh api -X DELETE "repos/$repo/issues/comments/$mine" >/dev/null 2>&1 </dev/null \
    || sa_tooling "lost the claim to another machine but cannot delete comment $mine"
  [ "$first" != null ] || sa_tooling "the claim comment vanished after posting"
  held_by_other "$first"
fi
answer taken "$first" 0
