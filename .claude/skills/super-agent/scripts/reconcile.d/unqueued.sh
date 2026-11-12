# Issues filed while a batch runs that nothing holds: offered once, then
# remembered (`unqueued_offered`). Sourced by `reconcile`, which calls it with
# `--fleet`. It reads and sets the caller's $doc, $errors and $unqueued, and reads
# $fleet and $batch_since.

# shellcheck disable=SC2154  # doc, errors, fleet and batch_since come from reconcile.sh and _lib.sh

reconcile_unqueued() {
  local repo raw issue key comments
  if [ -n "$fleet" ] && [ -n "$batch_since" ]; then
    while IFS= read -r repo; do
      [ -n "$repo" ] || continue
      raw=$(gh api "repos/$repo/issues?state=open&sort=created&direction=desc&per_page=100" 2>/dev/null </dev/null) || raw=''
      if ! jq -e 'type == "array"' <<<"$raw" >/dev/null 2>&1; then
        errors=$(jq -c --arg r "$repo" '. + [{key: $r, kind: "repo-unreadable", detail: {repo: $r}}]' <<<"$errors"); continue
      fi
      while IFS= read -r issue; do
        [ -n "$issue" ] || continue
        key="$repo#$(jq -r .number <<<"$issue")"
        if jq -e --arg k "$key" "$sa_jq_norm"'(.entries | keys | map(norm_repo)) + ((.waiting // []) | map(.key | norm_repo)) + ((.unqueued_offered // []) | map(norm_repo)) | index($k | norm_repo)' <<<"$doc" >/dev/null; then continue; fi
        comments=$(gh api "repos/$repo/issues/$(jq -r .number <<<"$issue")/comments?per_page=100" 2>/dev/null </dev/null) || comments=''
        if ! jq -e 'type == "array" and length < 100' <<<"$comments" >/dev/null 2>&1; then
          errors=$(jq -c --arg k "$key" '. + [{key: $k, kind: "claim-unreadable", detail: {key: $k}}]' <<<"$errors"); continue
        fi
        if jq -e 'any(.[]; (.body // "") | test("^<!-- super-agent-claim "))' <<<"$comments" >/dev/null; then continue; fi
        unqueued=$(jq -c --arg k "$key" --argjson i "$issue" '. + [{key: $k, title: $i.title, created_at: $i.created_at}]' <<<"$unqueued")
        doc=$(jq -c --arg k "$key" '.unqueued_offered = ((.unqueued_offered // []) + [$k])' <<<"$doc")
      done < <(jq -c --arg since "$batch_since" '.[] | select(.pull_request == null and .created_at >= $since)' <<<"$raw")
    done < <(jq -r '(.active_repos // [])[]' "$fleet")
  fi
}
