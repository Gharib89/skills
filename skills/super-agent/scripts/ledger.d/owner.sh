# A repo's reviewer limit and the owner's overrides on an entry: the arms of `ledger`
# that `limit`, `unlimit`, `take`, `tell`, `drop`, `reset-stalls` and `self` take,
# sourced by it (the needs are `ledger.d/needs.sh`). They read the
# caller's $usage, $ledger and $doc, which `ledger.sh` sets.

# shellcheck disable=SC2154  # usage, ledger, sa_jq_norm, sa_jq_open and sa_jq_tell come from ledger.sh and _lib.sh

ledger_owner() {
  local cmd=$1 key thread row had repo reviewer now now_s stalls ruling
  shift
  case $cmd in
  self)
    key=${1:-${T3CODE_THREAD_ID:-}}
    [ $# -le 1 ] && [ -n "$key" ] || sa_tooling "$usage"
    sa_update "$ledger" '.own_thread = $t' --arg t "$key"
    jq -cn --arg t "$key" '{own_thread: $t}' ;;
  tell)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_lock "$ledger"; sa_read "$ledger"
    key=$(sa_key "$doc" "$1")
    # a key names its entry's thread; anything else is a thread id the ledger need not hold
    thread=$(jq -r --arg k "$key" '.entries[$k].thread // empty' <<<"$doc")
    if [ -n "$thread" ]; then ruling="Owner tell: one send into $key's thread $thread."
    else
      case $1 in *#*|task:*) sa_fail "$1 is not in the ledger, or has no thread yet" ;; esac
      thread=$1 ruling="Owner tell: one send into thread $thread."
    fi
    now_s=$(sa_now_s); now=$(jq -rn --argjson s "$now_s" '$s | todate')
    ruling=$(sa_ruling_row "$ruling")
    # the tells that lapsed (`tell_live`, the call guard's own rule) are dropped, so the list
    # holds the last hour's tells alone
    sa_update "$ledger" "$sa_jq_tell"'.tells = ([(.tells // [])[] | select(.at | tell_live($s))]
      + [{thread: $t, at: $now}]) | .rulings += [$r]' --arg t "$thread" --arg now "$now" --argjson s "$now_s" --argjson r "$ruling"
    jq -cn --arg t "$thread" --arg now "$now" --argjson r "$ruling" '{thread: $t, at: $now, ruling: $r}' ;;
  take|drop|reset-stalls)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_lock "$ledger"; sa_read "$ledger"
    key=$(sa_key "$doc" "$1")
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$1 is not in the ledger"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    case $cmd in
    take)
      jq -e --arg k "$key" "$sa_jq_open"'.entries[$k] | is_open' <<<"$doc" >/dev/null || sa_fail "$key has ended: nothing to take"
      # the owner's now: its open needs are cleared, since nothing is the super agent's to ask about
      sa_update "$ledger" "$sa_jq_norm"'.entries[$k] |= (.owner_run = true | .owner_run_since = $now | .owner_run_reminded = false | .steered = false | .updated_at = $now)
        | .needs = ((.needs // []) | map(select((.key | norm_repo) != ($k | norm_repo))))' --arg k "$key" --arg now "$now"
      jq -cn --arg k "$key" '{key: $k, owner_run: true}' ;;
    drop)
      sa_update "$ledger" 'del(.entries[$k])' --arg k "$key"
      jq -cn --arg k "$key" '{key: $k, removed: true}' ;;
    reset-stalls)
      jq -e --arg k "$key" "$sa_jq_open"'.entries[$k] | is_open' <<<"$doc" >/dev/null || sa_fail "$key has ended: no stalls to reset"
      stalls=$(jq -r --arg k "$key" '.entries[$k].stalls // 0' <<<"$doc")
      ruling=$(sa_ruling_row "Owner reset-stalls: $key from $stalls stalls to 0.")
      sa_update "$ledger" '.entries[$k] |= (.stalls = 0 | .rest_since = null | .updated_at = $now) | .rulings += [$r]' \
        --arg k "$key" --arg now "$now" --argjson r "$ruling"
      jq -cn --arg k "$key" --argjson r "$ruling" '{key: $k, stalls: 0, ruling: $r}' ;;
    esac ;;
  limit)
    [ $# -eq 3 ] && [ "$2" = --reviewer ] || sa_tooling "$usage"
    repo=$1; sa_flag_value "$usage" "$3"; reviewer=$3
    case $repo in */*) ;; *) sa_tooling "$usage" ;; esac
    sa_lock "$ledger"; sa_read "$ledger"
    # A repeat keeps the first row: the first notice's time is the record.
    row=$(jq -cn --arg r "$repo" --arg w "$reviewer" --argjson nows "$(sa_epoch)" \
      --argjson old "$(jq -c --arg r "$repo" "$sa_jq_norm"'(.review_limits // []) | map(select((.repo | norm_repo) == ($r | norm_repo))) | first // null' <<<"$doc")" \
      '$old // {repo: $r, reviewer: $w, since: (($nows // now) | strftime("%Y-%m-%dT%H:%M:%SZ"))}')
    sa_update "$ledger" "$sa_jq_norm"'.review_limits = ((.review_limits // []) | map(select((.repo | norm_repo) != ($r | norm_repo))) + [$l])' --arg r "$repo" --argjson l "$row"
    jq -cn --argjson l "$row" '{limit: $l}' ;;
  unlimit)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_lock "$ledger"; sa_read "$ledger"
    had=$(jq -r --arg r "$1" "$sa_jq_norm"'[(.review_limits // [])[] | select((.repo | norm_repo) == ($r | norm_repo))] | length > 0' <<<"$doc")
    [ "$had" != true ] || sa_update "$ledger" "$sa_jq_norm"'.review_limits = ((.review_limits // []) | map(select((.repo | norm_repo) != ($r | norm_repo))))' --arg r "$1"
    jq -cn --arg r "$1" --argjson h "$had" '{repo: $r, removed: $h}' ;;
  esac
}
