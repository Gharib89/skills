# The settled triage re-read, sourced by `reconcile`. A settled triage entry is
# read again, thread only, for sa_settled_days after it settled: a grill that
# runs again after its owner answers must not go unwatched, and an older one is
# not read at all, so reconcile does not slow as history grows. An entry settled
# with no `observed` baseline has nothing to compare and is skipped, and an
# unreadable thread is left alone (a deleted one would otherwise error on every
# reconcile). A paused entry is the owner's and is not read. It moves $doc and
# appends to $woke.

# shellcheck disable=SC2154  # doc, now, now_s, woke and sa_jq_settled_before come from reconcile.sh and _lib.sh

reconcile_woke() {
  local entry key stage
  while IFS= read -r entry; do
    key=$(jq -r .key <<<"$entry")
    sa_thread_only=1 sa_observe "$entry" || continue
    stage=$(jq -r 'if $e.observed.run_count == null then "" elif .status == "running" then "running" elif .run_count > $e.observed.run_count then "at-rest" else "" end' --argjson e "$entry" <<<"$obs")
    [ -n "$stage" ] || continue
    doc=$(jq -c --arg k "$key" --arg s "$stage" --argjson o "$obs" --arg now "$now" \
      '.entries[$k] |= (.stage = $s | .observed += $o | .rest_since = null | .updated_at = $now)' <<<"$doc")
    woke=$(jq -c --argjson e "$entry" '. + [{key: $e.key, thread: $e.thread, kind: $e.kind}]' <<<"$woke")
  done < <(jq -c --argjson cut "$((now_s - sa_settled_days * 86400))" "$sa_jq_settled_before"'.entries[]
    | select(.stage == "settled" and .kind == "triage" and .paused != true and (settled_before($cut) | not))' <<<"$doc")
}
