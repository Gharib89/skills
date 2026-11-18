# A ruling's row and its lapse (ADR 0021), sourced by _lib.sh: sa_jq_live, sa_today
# and sa_ruling_row, the one builder of a row under `rulings`.

# A ruling's `expiry`, the last day it is in force, 7 days after its date; and
# whether it is `live($today)` (YYYY-MM-DD, sa_today): pinned, or on or before its
# `expires`, which one written before expiries lacks.
# shellcheck disable=SC2034  # read by ledger.sh and ledger.d/rulings.sh
sa_jq_live='def expiry: .date + "T00:00:00Z" | fromdateiso8601 + 7 * 86400 | strftime("%Y-%m-%d");
  def live($today): .pinned == true or (.expires // expiry) >= $today;'

# sa_today: the UTC date of sa_now_s, so `SA_NOW` pins a ruling's date and lapse.
sa_today() { date -u -d "@$(sa_now_s)" +%F; }

# sa_ruling_row <text> [<allow json> [<repo>]]: a ruling row dated sa_today, unpinned,
# lapsing at its `expiry`: the one shape `ledger` writes under `rulings`
sa_ruling_row() {
  jq -cn --arg d "$(sa_today)" --arg t "$1" --argjson a "${2:-[]}" --arg r "${3:-}" "$sa_jq_live"'
    {date: $d, text: $t, allow: $a, repo: (if $r == "" then null else $r end)} | .expires = expiry | .pinned = false'
}
