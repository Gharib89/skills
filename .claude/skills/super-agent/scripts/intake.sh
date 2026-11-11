#!/usr/bin/env bash
# The daily offer: list the open `ready-for-agent` issues of the fleet file's
# active repos that this super agent may take. It reads GitHub and the ledger
# and writes nothing, launches nothing and claims nothing: the owner's go on a
# ticket is what launches it, through `claim` and `place`.
#
#   intake --fleet <file> --ledger <file> --machine <key> --thread <id>
#          [--stale-after <seconds>] [--now <iso time>]
#
# A ticket is left out of `offer` when the ledger already holds it open, when
# another machine's claim holds it (`claimed`), or when that claim is past the
# stale window (`stale`, offered back to the owner rather than taken). A claim
# of this machine does not hold it back. --machine, --thread, --stale-after and
# --now are `claim`'s and are passed to its --check, which decides each ticket.
#
# stdout: {repos, offer, held, claimed, stale, errors}: `repos` the active
#         repos scanned; `offer` one {key, title, labels} per ticket, repos in
#         the file's order and tickets by number; `held` the keys the ledger
#         holds; `claimed` and `stale` one {key, machine, age_s} each; `errors`
#         one {repo, error} for a repo whose issues could not be read, or
#         {key, error} for a ticket whose claim could not be
# exit: 0 an answer, errors included · 2 usage, or an unreadable fleet file or
#       ledger
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: intake --fleet <file> --ledger <file> --machine <key> --thread <id> [--stale-after <seconds>] [--now <iso time>]'
sa_help "$usage" "$@"
fleet='' ledger='' machine='' thread='' claim_args=()
while [ $# -gt 0 ]; do
  case $1 in
    --fleet|--ledger|--machine|--thread|--stale-after|--now) sa_flag_value "$usage" "${2:-}" ;;
    *) sa_tooling "$usage" ;;
  esac
  case $1 in
    --fleet) fleet=$2 ;; --ledger) ledger=$2 ;; --machine) machine=$2 ;; --thread) thread=$2 ;;
    --stale-after) sa_window_flag "$usage" "$2"; claim_args+=("$1" "$2") ;;
    --now) claim_args+=("$1" "$2") ;;
  esac
  shift 2
done
[ -n "$fleet" ] && [ -n "$ledger" ] && [ -n "$machine" ] && [ -n "$thread" ] || sa_tooling "$usage"
[ -f "$fleet" ] || sa_tooling "$fleet: no such file"
jq -e '((.active_repos // []) | type == "array" and all(type == "string"))' "$fleet" >/dev/null 2>&1 \
  || sa_tooling "$fleet: not JSON, or active_repos is not an array of strings"
sa_read "$ledger"
here=$(dirname "${BASH_SOURCE[0]}")

repos=$(jq -c '.active_repos // []' "$fleet")
offer='[]' held='[]' claimed='[]' stale='[]' errors='[]'
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  raw=$(gh api --paginate "repos/$repo/issues?state=open&labels=ready-for-agent&per_page=100" 2>/dev/null </dev/null) \
    && list=$(jq -sc '(add // []) | map(select(.pull_request == null)) | sort_by(.number)' <<<"$raw" 2>/dev/null) \
    && jq -e 'type == "array"' <<<"$list" >/dev/null 2>&1 \
    || { errors=$(jq -c --arg r "$repo" '. + [{repo: $r, error: "cannot read its ready-for-agent issues"}]' <<<"$errors"); continue; }
  while IFS= read -r issue; do
    [ -n "$issue" ] || continue
    n=$(jq -r .number <<<"$issue") key="$repo#$n"
    if jq -e --arg k "$key" "$sa_jq_open$sa_jq_norm"' [.entries[] | select((.key | norm_repo) == ($k | norm_repo)) | select(is_open)] | length > 0' <<<"$doc" >/dev/null; then
      held=$(jq -c --arg k "$key" '. + [$k]' <<<"$held"); continue
    fi
    out=$(bash "$here/claim.sh" --check --repo "$repo" --number "$n" --machine "$machine" --thread "$thread" ${claim_args[@]+"${claim_args[@]}"} 2>/dev/null </dev/null)
    case $(jq -r '.status // empty' <<<"$out" 2>/dev/null) in
      free|own) offer=$(jq -c --arg k "$key" --argjson i "$issue" '. + [{key: $k, title: $i.title, labels: [$i.labels[].name]}]' <<<"$offer") ;;
      claimed) claimed=$(jq -c --arg k "$key" --argjson o "$out" '. + [{key: $k, machine: $o.claim.machine, age_s: $o.claim.age_s}]' <<<"$claimed") ;;
      stale) stale=$(jq -c --arg k "$key" --argjson o "$out" '. + [{key: $k, machine: $o.claim.machine, age_s: $o.claim.age_s}]' <<<"$stale") ;;
      *) errors=$(jq -c --arg k "$key" '. + [{key: $k, error: "cannot read its claim"}]' <<<"$errors") ;;
    esac
  done < <(jq -c '.[]' <<<"$list")
done < <(jq -r '.[]' <<<"$repos")

jq -cn --argjson repos "$repos" --argjson o "$offer" --argjson h "$held" --argjson c "$claimed" --argjson s "$stale" --argjson e "$errors" \
  '{repos: $repos, offer: $o, held: $h, claimed: $c, stale: $s, errors: $e}'
