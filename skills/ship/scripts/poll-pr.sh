#!/usr/bin/env bash
# ship phases 7 and 8: one bounded, foreground poll of a PR's head, checks,
# reviews and threads, then ONE JSON summary.
#
#   poll-pr <pr> [--await-review <login>] [--since <iso>] [--timeout <s>] [--interval <s>]
#
# done when the PR is in conflict (merge-ref checks never start, so waiting is
# pointless), or every check on the head has completed and, with --await-review,
# a SUBSTANTIVE review by that login has landed. `substantive` is the landing
# signal: a reviewer's reply to one thread posts as a review row of its own
# (current head, empty body), so only a body is a round.
#
# Two landing rules, chosen by the reviewer's profile `Trigger:`; `landed_by`
# names the one that matched.
#   head (default, on-push): the review sits on the current head. Every push
#     earns a new review, so a review on an older commit does not count.
#   since (--since, on-request and auto-once): the review was submitted at or
#     after <iso>, on ANY head. Such a reviewer delivers one round per request
#     and never re-posts, so a push between the request and the review leaves
#     the round keyed to the older head; the head rule would wait forever.
#     Pass `request-review`'s `requested_at` (on-request) or the PR's creation
#     time (auto-once). Matching by time, not by request login, is deliberate:
#     the login a request is made under and the login the host records can
#     differ. A row with a null submitted_at is host state rather than a timed
#     event (an Azure DevOps vote) and counts under either rule.
#
# `reviewer_blocked` non-null with done=false means the round is WAITING (a
# quota or queue notice), not missing. `threads` is "unavailable" when thread
# state could not be read (GraphQL refused): that reviewer's exit is degraded
# unreachable, the run proceeds.
#
# stdout: {head_sha, mergeable, checks[], reviews: {on_head[], all[], total},
#          threads, reviewer_blocked, landed_by, done, waited_s}
# exit: 0 done · 1 window closed first (done=false; re-run to extend) · 2 tooling
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
pr=${1:?usage: poll-pr <pr> [--await-review <login>] [--since <iso>] [--timeout <s>] [--interval <s>]}; shift
timeout=480; interval=20; await=""; since=""
while [ $# -gt 0 ]; do
  case $1 in
    --await-review) await=${2:?}; shift 2 ;;
    --since) since=${2:?}; shift 2 ;;
    --timeout) timeout=${2:?}; shift 2 ;;
    --interval) interval=${2:?}; shift 2 ;;
    *) ship_tooling "unknown flag: $1" ;;
  esac
done
[ -z "$since" ] || [ -n "$await" ] || ship_tooling "--since needs --await-review"
ship_load_host

norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/\[bot\]$//'; }
start=$SECONDS
while :; do
  prj=$(host_pr_get "$pr") || ship_tooling "cannot read PR $pr"
  sha=$(jq -r .head_sha <<<"$prj"); mergeable=$(jq -r .mergeable <<<"$prj")
  checks=$(host_pr_checks "$pr" "$sha") || ship_tooling "cannot read checks"
  reviews=$(host_pr_reviews "$pr" "$sha") || ship_tooling "cannot read reviews"
  threads=$(host_pr_threads "$pr") || threads='"unavailable"'
  blocked=null
  [ -z "$await" ] || blocked=$(host_pr_reviewer_blocked "$pr" "$await") || blocked=null

  pending=$(jq '[.[] | select(.status == "pending")] | length' <<<"$checks")
  landed=true; landed_by=null
  if [ -n "$await" ]; then
    landed_by=$(jq -c --arg l "$(norm "$await")" --arg s "$since" '
      def mine: [.[] | select(.substantive and ((.login | ascii_downcase | sub("\\[bot\\]$"; "")) == $l))];
      if $s == "" then (if (.on_head | mine) != [] then "head" else null end)
      else (if (.all | mine | map(select(.submitted_at == null or .submitted_at >= $s))) != [] then "since" else null end)
      end' <<<"$reviews")
    [ "$landed_by" != null ] || landed=false
  fi
  done=false
  if [ "$mergeable" = conflict ]; then done=true
  elif [ "$pending" -eq 0 ] && [ "$landed" = true ]; then done=true
  fi
  waited=$((SECONDS - start))
  if $done || [ "$waited" -ge "$timeout" ]; then
    jq -n --arg sha "$sha" --arg m "$mergeable" --argjson c "$checks" --argjson r "$reviews" \
      --argjson t "$threads" --argjson b "$blocked" --argjson lb "$landed_by" --argjson d "$done" --argjson w "$waited" \
      '{head_sha: $sha, mergeable: $m, checks: $c, reviews: $r, threads: $t, reviewer_blocked: $b,
        landed_by: $lb, done: $d, waited_s: $w}'
    $done
    exit
  fi
  sleep "$interval"
done
