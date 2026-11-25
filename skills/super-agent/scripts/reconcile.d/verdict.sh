# The stall count `reconcile` keeps for one entry, and what it reads of the owner's hand
# in it, sourced by it: the verdict of a run or a rest on the stall count (`reconcile_judge`),
# whether the owner spoke last in a thread (`steered`), and the one reminder for an entry the
# owner took 3 days ago (`owner-run`). They read and write the caller's $doc, $key, $entry,
# $obs, $now, $now_s, $window, $active, $reads and $sa_remote_dirs, and set $stalls and
# $stall and append to $reminders and $steered_due.

# shellcheck disable=SC2154,SC2034  # stalls and stall are read by reconcile.sh; doc, key, entry, obs, now, now_s, window, active, reads, reminders, steered_due and sa_remote_dirs come from reconcile.sh and _lib.sh

# reconcile_steered <entry>: `true` when the entry's reply file (`reply.sh`: `owner_at`,
# when the owner's message was the newest from outside the thread) names a message newer
# than `held_since`, else `launched_at`, so a thread the owner started and then handed over
# is not steered by its own first message; `false` when it does not. An entry with no reply
# file to read keeps the mark it has. A local entry's file is in `--reads`, a remote one's
# in its `--remote`.
reconcile_steered() {
  local t env d
  t=$(jq -r .thread <<<"$1") env=$(jq -r '.environment_id // empty' <<<"$1")
  if [ -n "$env" ]; then d=$(jq -r --arg e "$env" '.[$e] // empty' <<<"$sa_remote_dirs"); else d=$reads; fi
  if [ -n "$d" ] && sa_thread_file_ok "$t" && [ -f "$d/$t.json" ]; then
    jq -r --argjson e "$1" 'def at: sub("[.][0-9]+Z$"; "Z") | fromdateiso8601;
      (.owner_at // null) as $o | ($e.held_since // $e.launched_at) as $h
      | $o != null and ($h == null or ($o | at) > ($h | at))' "$d/$t.json" 2>/dev/null && return 0
  fi
  jq -r '.steered == true' <<<"$1"
}

# reconcile_owner_run_reminder <entry>: the entry has been owner-run for 3 days and was
# not yet reminded: mark it so and list one `owner-run` row, once.
reconcile_owner_run_reminder() {
  jq -e --argjson now "$now_s" '.owner_run_reminded != true and .owner_run_since != null
    and $now - (.owner_run_since | fromdateiso8601) >= 3 * 86400' <<<"$1" >/dev/null || return 0
  doc=$(jq -c --arg k "$key" '.entries[$k].owner_run_reminded = true' <<<"$doc")
  reminders=$(jq -c --arg k "$key" --arg t "$(jq -r .thread <<<"$1")" '. + [{key: $k, thread: $t, reason: "owner-run", detail: "still yours: watch or drop?"}]' <<<"$reminders")
}

# reconcile_judge: the stall verdict of the entry in $entry, whose snapshot is $obs, written
# into $doc as its `stalls`, `rest_since`, `judged_run` and `steered`; $stalls is the count and
# $stall `run-completed` or `stall-window` when one was counted now. A steered entry counts
# none: it is 0 and judged to the run count, and a rest past the window is one `steered_due` row.
reconcile_judge() {
  local steered verdict
  steered=$(reconcile_steered "$entry")
  verdict=$(jq -cn --argjson e "$entry" --argjson n "$obs" --arg now "$now" --argjson w "$window" --argjson active "$active" --argjson steered "$steered" '
    def down: if . > 0 then . - 1 else 0 end;
    ($now | fromdateiso8601) as $t
    | {stalls: ($e.stalls // 0), rest_since: $e.rest_since, judged_run: ($e.judged_run // 0), stall: null, due: false}
    | if $steered then
        # the owner spoke last: no stall, and a rest past the window is one need, never a nudge
        .stalls = 0 | .judged_run = $n.run_count
        | if $active or $n.pending > 0 then .rest_since = null
          elif .rest_since == null then .rest_since = $now
          elif $t - (.rest_since | fromdateiso8601) >= $w then .rest_since = $now | .due = true
          else . end
      elif $e.observed == null then (if $e.resumed == true then .judged_run = $n.run_count else . end)
      else
        (if $e.observed.pr.state == "none" and $n.pr.state == "open" then .stalls |= down else . end)
        | if $active or $n.pending > 0 then .rest_since = null
          elif $n.gate then
            (if $n.run_count > .judged_run then .stalls |= down | .judged_run = $n.run_count else . end) | .rest_since = null
          elif .stalls >= 3 then .judged_run = $n.run_count
          elif $n.run_count > .judged_run then
            .stalls += 1 | .judged_run = $n.run_count | .rest_since = $now | .stall = "run-completed"
          elif .rest_since == null then .rest_since = $now
          elif $t - (.rest_since | fromdateiso8601) >= $w then
            .stalls += 1 | .rest_since = $now | .stall = "stall-window"
          else . end
      end')
  stalls=$(jq -r .stalls <<<"$verdict") stall=$(jq -r '.stall // ""' <<<"$verdict")
  doc=$(jq -c --arg k "$key" --argjson v "$verdict" --argjson st "$steered" \
    '.entries[$k] |= (.stalls = $v.stalls | .rest_since = $v.rest_since | .judged_run = $v.judged_run
      | if (.steered == true) != $st then .steered = $st else . end)' <<<"$doc")
  if [ "$(jq -r .due <<<"$verdict")" = true ]; then
    steered_due=$(jq -c --arg k "$key" --arg t "$(jq -r .thread <<<"$entry")" '. + [{key: $k, thread: $t}]' <<<"$steered_due")
  fi
}
