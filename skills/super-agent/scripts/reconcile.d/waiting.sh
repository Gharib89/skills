# The waiting list: the owner's queue. A closed issue drops its row; a row is
# ready when its blocker merged and its repo has a free ship slot. Sourced by
# `reconcile`. It reads and sets the caller's $doc, $ready and $dropped, reads
# $fleet, and calls the caller's `issue_read` and `unreadable` (which records the
# error).

# shellcheck disable=SC2154  # doc, ready, dropped and fleet come from reconcile.sh and _lib.sh

reconcile_waiting() {
  local row key repo issue state after blocker bstate max used
  ready='[]' dropped='[]'
  while IFS= read -r row; do
    key=$(jq -r .key <<<"$row") repo=$(jq -r .repo <<<"$row")
    issue=$(issue_read "$repo" "$(jq -r .number <<<"$row")") || issue=''
    state=$(jq -r '.state // empty' <<<"$issue" 2>/dev/null)
    if [ -z "$state" ]; then unreadable "$key" "$key"; continue; fi
    if [ "$state" = closed ]; then
      doc=$(jq -c --arg k "$key" "$sa_jq_norm"'.waiting |= map(select((.key | norm_repo) != ($k | norm_repo)))' <<<"$doc")
      dropped=$(jq -c --arg k "$key" '. + [{key: $k, reason: "issue-closed"}]' <<<"$dropped"); continue
    fi
    after=$(jq -r '.after // empty' <<<"$row")
    if [ -n "$after" ] && ! jq -e --arg k "$after" "$sa_jq_norm"'[.entries[] | select(.key | norm_repo == ($k | norm_repo)) | .stage] | any(IN("merged", "settled"))' <<<"$doc" >/dev/null; then
      blocker=$(issue_read "${after%#*}" "${after##*#}") || blocker=''
      bstate=$(jq -r '.state // empty' <<<"$blocker" 2>/dev/null)
      if [ -z "$bstate" ]; then unreadable "$key" "$after"; continue; fi
      # A closed issue means merged unless it was closed as not planned.
      [ "$bstate" = closed ] && [ "$(jq -r '.state_reason // empty' <<<"$blocker")" != not_planned ] || continue
    fi
    max=$([ -z "$fleet" ] || jq -r --arg r "$repo" "$sa_jq_norm"'[(.repos // {}) | to_entries[] | select(.key | norm_repo == ($r | norm_repo)) | .value.max_ships] | first // empty' "$fleet")
    used=$(jq -r --arg r "$repo" --argjson ready "$ready" "$sa_jq_open$sa_jq_norm"'[.entries[] | select(is_open and ((.repo // "") | norm_repo) == ($r | norm_repo))] | length + ([$ready[] | select(.repo | norm_repo == ($r | norm_repo))] | length)' <<<"$doc")
    [ "$used" -lt "${max:-3}" ] || continue
    ready=$(jq -c --argjson r "$row" '. + [$r | {key, repo, order, after, reason, since}]' <<<"$ready")
  done < <(jq -c "$sa_jq_waiting"'waiting_list[]' <<<"$doc")
  ready=$(jq -c 'map(del(.repo))' <<<"$ready")
}
