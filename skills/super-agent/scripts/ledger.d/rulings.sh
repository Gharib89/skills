# The owner's rulings and their lapse (ADR 0021): the arms of `ledger` that
# `ruling`, `allowed`, `scoped`, `pin` and `migrate-rulings` take, sourced by it.
# They read the caller's $usage and $ledger, which `ledger.sh` sets.

# shellcheck disable=SC2154  # usage, ledger, sa_jq_norm and sa_jq_live come from ledger.sh and _lib.sh

ledger_rulings() {
  local cmd=$1 list today yesterday missing text allow rrepo ruling srepo
  shift
  today=$(sa_today) yesterday=$(date -u -d "@$(($(sa_now_s) - 86400))" +%F)
  case $cmd in
  ruling)
    [ $# -ge 1 ] || sa_tooling "$usage"
    text=$1; shift; allow='[]' rrepo=''
    while [ $# -gt 0 ]; do
      case $1 in
        --brief|--machine) sa_tooling "ruling $1 is retired: no launch message or machine scope reads a ruling. $(sa_brief_where)" ;;
        --repo) sa_flag_value "$usage" "${2:-}"; rrepo=$2; shift 2 ;;
        --allow) sa_flag_value "$usage" "${2:-}"; allow=$(jq -c --arg c "$2" '. + [$c]' <<<"$allow"); shift 2 ;;
        *) sa_tooling "$usage" ;;
      esac
    done
    ruling=$(jq -cn --arg d "$today" --arg t "$text" --argjson a "$allow" --arg r "$rrepo" \
      '{date: $d, text: $t, allow: $a, repo: (if $r == "" then null else $r end),
        expires: ($d + "T00:00:00Z" | fromdateiso8601 + 7 * 86400 | strftime("%Y-%m-%d")), pinned: false}')
    sa_update "$ledger" '.rulings += [$r]' --argjson r "$ruling"
    jq -cn --argjson r "$ruling" '{ruling: $r}' ;;
  allowed)
    [ $# -eq 0 ] || sa_tooling "$usage"
    sa_read "$ledger"
    jq -c --arg today "$today" "$sa_jq_live"'{allowed: [.rulings[] | select(live($today)) | .date as $d | (.allow // [])[] | {date: $d, call: .,
      line: "Run `\(.)` without a hold: the owner allowed it on \($d)."}]}' <<<"$doc" ;;
  scoped)
    srepo=''
    case $# in 0) ;; 2) [ "$1" = --repo ] || sa_tooling "$usage"; sa_flag_value "$usage" "$2"; srepo=$2 ;; *) sa_tooling "$usage" ;; esac
    sa_read "$ledger"
    jq -c --arg r "$srepo" --arg today "$today" "$sa_jq_norm$sa_jq_live"'{scoped: [.rulings[] | select(live($today)) | select(.repo != null and ($r == "" or (.repo | norm_repo) == ($r | norm_repo))) | {date, text, repo}]}' <<<"$doc" ;;
  pin)
    [ $# -eq 2 ] || sa_tooling "$usage"
    sa_lock "$ledger"; sa_read "$ledger"
    jq -e --arg d "$1" --arg t "$2" 'any(.rulings[]; .date == $d and .text == $t)' <<<"$doc" >/dev/null \
      || sa_fail "no ruling dated $1 reads: $2"
    sa_update "$ledger" '.rulings |= map(if .date == $d and .text == $t then .pinned = true else . end)' --arg d "$1" --arg t "$2"
    jq -c --arg d "$1" --arg t "$2" '{pinned: [.rulings[] | select(.date == $d and .text == $t)]}' <<<"$doc" ;;
  migrate-rulings)
    # The owner-approved list: [{date, text, mark: pin|lapse|move, to}], `to`
    # naming the fleet key or ship profile line a moved ruling now lives in.
    [ $# -eq 1 ] || sa_tooling "$usage"
    list=$(jq -c . "$1" 2>/dev/null) || sa_tooling "$1: not JSON"
    jq -e 'type == "array" and all(.[]; (.date | type) == "string" and (.text | type) == "string"
      and (.mark | IN("pin", "lapse", "move")) and (.mark != "move" or ((.to | type) == "string" and .to != "")))' <<<"$list" >/dev/null \
      || sa_tooling "$1: want [{date, text, mark: pin|lapse|move, to}], a move naming its destination in to"
    sa_lock "$ledger"; sa_read "$ledger"
    jq -e '.rulings_migrated == null' <<<"$doc" >/dev/null || sa_fail "the rulings were migrated on $(jq -r .rulings_migrated <<<"$doc"); the migration runs once"
    missing=$(jq -r --argjson l "$list" '. as $d | $l[] | select(. as $i | any($d.rulings[]; .date == $i.date and .text == $i.text) | not)
      | "\(.date) \(.text)"' <<<"$doc")
    [ -z "$missing" ] || sa_fail "the list names rulings the ledger lacks: $(paste -sd';' <<<"$missing")"
    # an unmarked ruling lapses, as one marked lapse does: its expiry becomes yesterday
    sa_update "$ledger" '.rulings |= map(. as $r | ([$l[] | select(.date == $r.date and .text == $r.text)] | first) as $m
        | if $m.mark == "pin" then .pinned = true
          elif $m.mark == "move" then .moved_to = $m.to | .pinned = false | .expires = $y
          else .pinned = false | .expires = $y end)
      | .rulings_migrated = $today' --argjson l "$list" --arg y "$yesterday" --arg today "$today"
    jq -c '{pinned: [.rulings[] | select(.pinned == true) | {date, text}],
      lapsed: [.rulings[] | select(.pinned != true and .moved_to == null) | {date, text}],
      moved: [.rulings[] | select(.moved_to != null) | {date, text, to: .moved_to}]}' <<<"$doc" ;;
  esac
}
