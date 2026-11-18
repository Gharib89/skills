# The owner's needs, a repo's reviewer limit and the owner's overrides on an entry: the
# arms of `ledger` that `need`, `pushed`, `unneed`, `limit`, `unlimit`, `pause`,
# `unpause`, `drop` and `reset-stalls` take, sourced by it. They read the
# caller's $usage, $ledger and $doc, which `ledger.sh` sets.

# shellcheck disable=SC2154  # usage, ledger, sa_jq_norm and sa_jq_open come from ledger.sh and _lib.sh

ledger_owner() {
  local cmd=$1 key action reason="" row had repo reviewer now stalls ruling
  shift
  case $cmd in
  pause|unpause|drop|reset-stalls)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_lock "$ledger"; sa_read "$ledger"
    key=$(sa_key "$doc" "$1")
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$1 is not in the ledger"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    case $cmd in
    pause)
      jq -e --arg k "$key" "$sa_jq_open"'.entries[$k] | is_open' <<<"$doc" >/dev/null || sa_fail "$key has ended: nothing to pause"
      sa_update "$ledger" '.entries[$k] |= (.paused = true | .updated_at = $now)' --arg k "$key" --arg now "$now"
      jq -cn --arg k "$key" '{key: $k, paused: true}' ;;
    unpause)
      # watching restarts from the thread as it is now: `resumed` has the next
      # reconcile take its run count as already judged
      sa_update "$ledger" '.entries[$k] |= (.paused = false | .observed = null | .rest_since = null | .resumed = true | .updated_at = $now)' \
        --arg k "$key" --arg now "$now"
      jq -cn --arg k "$key" '{key: $k, paused: false}' ;;
    drop)
      sa_update "$ledger" 'del(.entries[$k])' --arg k "$key"
      jq -cn --arg k "$key" '{key: $k, removed: true}' ;;
    reset-stalls)
      stalls=$(jq -r --arg k "$key" '.entries[$k].stalls // 0' <<<"$doc")
      ruling=$(jq -cn --arg d "$(date -u +%F)" --arg t "Owner reset-stalls: $key from $stalls stalls to 0." '{date: $d, text: $t, allow: [], repo: null}')
      sa_update "$ledger" '.entries[$k] |= (.stalls = 0 | .rest_since = null | .updated_at = $now) | .rulings += [$r]' \
        --arg k "$key" --arg now "$now" --argjson r "$ruling"
      jq -cn --arg k "$key" --argjson r "$ruling" '{key: $k, stalls: 0, ruling: $r}' ;;
    esac ;;
  need)
    { [ $# -eq 3 ] || [ $# -eq 5 ]; } && [ "$2" = --action ] || sa_tooling "$usage"
    key=$1; sa_flag_value "$usage" "$3"; action=$3
    if [ $# -eq 5 ]; then [ "$4" = --reason ] || sa_tooling "$usage"; sa_flag_value "$usage" "$5"; reason=$5; fi
    case $key in task:?*) ;; */*#*[0-9]) case ${key##*#} in *[!0-9]*) sa_tooling "$usage" ;; esac ;; *) sa_tooling "$usage" ;; esac
    case $action in *$'\n'*) sa_tooling "an action is one line" ;; esac
    sa_lock "$ledger"; sa_read "$ledger"
    row=$(jq -cn --arg k "$key" --arg a "$action" --arg why "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson old "$(jq -c --arg k "$key" "$sa_jq_norm"'(.needs // []) | map(select((.key | norm_repo) == ($k | norm_repo))) | first // null' <<<"$doc")" \
      '(if $old != null and $old.action == $a and ($old.reason // "") == $why then $old else {key: $k, action: $a, since: $now, pushed: false} + (if $why == "" then {} else {reason: $why} end) end)')
    sa_update "$ledger" "$sa_jq_norm"'.needs = ((.needs // []) | map(select((.key | norm_repo) != ($k | norm_repo))) + [$n])' --arg k "$key" --argjson n "$row"
    jq -cn --argjson n "$row" '{need: $n}' ;;
  pushed)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_lock "$ledger"; sa_read "$ledger"
    jq -e --arg k "$1" "$sa_jq_norm"'[(.needs // [])[] | select((.key | norm_repo) == ($k | norm_repo))] | length > 0' <<<"$doc" >/dev/null || sa_fail "$1 has no open need"
    sa_update "$ledger" "$sa_jq_norm"'.needs |= map(if (.key | norm_repo) == ($k | norm_repo) then .pushed = true else . end)' --arg k "$1"
    jq -cn --argjson n "$(jq -c --arg k "$1" "$sa_jq_norm"'.needs[] | select((.key | norm_repo) == ($k | norm_repo))' <<<"$doc")" '{need: $n}' ;;
  unneed)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_lock "$ledger"; sa_read "$ledger"
    had=$(jq -r --arg k "$1" "$sa_jq_norm"'[(.needs // [])[] | select((.key | norm_repo) == ($k | norm_repo))] | length > 0' <<<"$doc")
    [ "$had" != true ] || sa_update "$ledger" "$sa_jq_norm"'.needs = ((.needs // []) | map(select((.key | norm_repo) != ($k | norm_repo))))' --arg k "$1"
    jq -cn --arg k "$1" --argjson r "$had" '{key: $k, removed: $r}' ;;
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
