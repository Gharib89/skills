# A usage-limit stop's reset time, sourced by _lib.sh for `sa_observe`.

# sa_limit_reset: replaces `limit` in $obs with `limit_reset` (absent when null, so a rest with no limit keeps the old snapshot shape), the epoch of the next occurrence of the
# limit line's clock time in its zone after the thread's `rest_at`; null when the line names none or
# `date` cannot read it or the zone is unknown, which leaves an ordinary rest.
sa_limit_reset() {
  local time tz rest_s day reset_s
  time=$(jq -r '.limit.time // empty' <<<"$obs") tz=$(jq -r '.limit.tz // empty' <<<"$obs") rest_s=$(jq -r '.rest_at // empty' <<<"$obs")
  reset_s=null
  # `date` reads a zone it does not know as UTC, so only a zone with a zoneinfo file is trusted
  if [ -n "$time" ] && [ -n "$rest_s" ] && [ -f "/usr/share/zoneinfo/$tz" ]; then
    day=$(TZ=$tz date -d "@$rest_s" +%F 2>/dev/null) || day=''
    if [ -n "$day" ] && reset_s=$(TZ=$tz date -d "$day $time" +%s 2>/dev/null); then
      [ "$reset_s" -gt "$rest_s" ] || reset_s=$(TZ=$tz date -d "$day $time + 1 day" +%s 2>/dev/null) || reset_s=null
    else reset_s=null; fi
  fi
  obs=$(jq -c --argjson a "${reset_s:-null}" 'del(.limit) + (if $a == null then {} else {limit_reset: $a} end)' <<<"$obs")
}
