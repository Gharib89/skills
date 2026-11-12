# The look at a spec parent that `reconcile` takes once per merged ship entry,
# sourced by it. A merged PR whose ticket is a sub-issue: once the ticket reads
# closed and every sub-issue of the open parent is closed, the parent is offered,
# once (the ledger keeps `parents_offered`). The entry's `parent_checked` ends its
# look; an unreadable ticket or parent is retried on a later wake. It reads the
# caller's $doc, sets its $parents_done and $parents_changed, and calls its
# `issue_read` and `unreadable` (which records the error).

# shellcheck disable=SC2034,SC2154  # parents_changed is read by reconcile.sh; doc and the helpers come from it and _lib.sh

reconcile_parents() {
  local entry key child cstate purl parent pkey praw
  while IFS= read -r entry; do
    key=$(jq -r .key <<<"$entry")
    child=$(issue_read "${key%#*}" "${key##*#}") || child=''
    cstate=$(jq -r '.state // empty' <<<"$child" 2>/dev/null)
    if [ -z "$cstate" ]; then unreadable "$key" "$key"; continue; fi
    [ "$cstate" = closed ] || continue
    purl=$(jq -r '.parent_issue_url // empty' <<<"$child")
    if [ -n "$purl" ]; then
      parent=${purl#*/repos/}; pkey="${parent%/issues/*}#${parent##*/}"
      praw=$(issue_read "${pkey%#*}" "${pkey##*#}") || praw=''
      if ! jq -e '.state' <<<"$praw" >/dev/null 2>&1; then unreadable "$key" "$pkey"; continue; fi
      if jq -e '.state == "open" and (.sub_issues_summary.total // 0) > 0 and .sub_issues_summary.completed == .sub_issues_summary.total' <<<"$praw" >/dev/null \
        && ! jq -e --arg k "$pkey" "$sa_jq_norm"'(.parents_offered // []) | map(norm_repo) | index($k | norm_repo)' <<<"$doc" >/dev/null; then
        parents_done=$(jq -c --arg k "$pkey" --argjson p "$praw" '. + [{key: $k, title: $p.title, sub_issues: $p.sub_issues_summary.total}]' <<<"$parents_done")
        doc=$(jq -c --arg k "$pkey" '.parents_offered = ((.parents_offered // []) + [$k])' <<<"$doc")
      fi
    fi
    doc=$(jq -c --arg k "$key" '.entries[$k].parent_checked = true' <<<"$doc") parents_changed=1
  done < <(jq -c '.entries[] | select((.kind // "ship") == "ship" and (.stage == "merged" or .stage == "settled") and .observed.pr.state == "merged" and .parent_checked != true)' <<<"$doc")
}
