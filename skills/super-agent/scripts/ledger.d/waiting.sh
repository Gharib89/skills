# The waiting list's arms of `ledger`, `wait` and `unwait`, sourced by it. They read
# the caller's $usage and $ledger, which `ledger.sh` sets.

# shellcheck disable=SC2154  # usage, ledger and the sa_jq_* helpers come from ledger.sh and _lib.sh

ledger_waiting() {
  local cmd=$1 key reason order after k row had ask trepo skill tkeys place
  shift
  case $cmd in
  wait)
    [ $# -ge 3 ] || sa_tooling "$usage"
    key=$1; shift; reason='' order='' after='' ask='' trepo='' skill='' place='{}'
    while [ $# -gt 0 ]; do
      case $1 in
        --gpu) place=$(jq -c '.gpu = true' <<<"$place"); shift; continue ;;
        --account) sa_flag_value "$usage" "${2:-}"; place=$(jq -c --arg v "$2" '.account = $v' <<<"$place") ;;
        --area|--exclude) sa_flag_value "$usage" "${2:-}"
          place=$(jq -c --arg f "$([ "$1" = --area ] && echo areas || echo exclude)" --arg v "$2" '.[$f] += [$v]' <<<"$place") ;;
        --reason) sa_flag_value "$usage" "${2:-}"; reason=$2 ;;
        --ask) sa_flag_value "$usage" "${2:-}"; ask=$2 ;;
        --repo) sa_flag_value "$usage" "${2:-}"; trepo=$2 ;;
        --skill) sa_flag_value "$usage" "${2:-}"; skill=$2 ;;
        --order) sa_flag_value "$usage" "${2:-}"; case $2 in ''|*[!0-9]*|??????????*) sa_tooling "$usage" ;; esac; order=$2 ;;
        --after) sa_flag_value "$usage" "${2:-}"; after=$2 ;;
        *) sa_tooling "$usage" ;;
      esac
      shift 2
    done
    [ -n "$reason" ] || sa_tooling "$usage"
    # a task's row carries what relaunches it (`launch task`: its ask, repo, skill and place
    # flags); a ticket's is read from its issue
    case $key in
      task:*) sa_task_slug_ok "${key#task:}" || sa_tooling "$usage"
        [ -n "$ask" ] && [ -z "$after" ] || sa_tooling "$usage"; tkeys=() ;;
      *) [ -z "$ask$trepo$skill" ] && [ "$place" = '{}' ] || sa_tooling "$usage"; tkeys=("$key") ;;
    esac
    for k in ${tkeys[@]+"${tkeys[@]}"} ${after:+"$after"}; do
      case $k in */*#*[0-9]) ;; *) sa_tooling "$usage" ;; esac
      case ${k##*#} in *[!0-9]*) sa_tooling "$usage" ;; esac
    done
    jq -en --arg a "$after" --arg k "$key" "$sa_jq_norm"'($a|norm_repo)!=($k|norm_repo)' >/dev/null || sa_tooling "$usage"
    sa_lock "$ledger"; sa_read "$ledger"
    jq -e --arg k "$(sa_key "$doc" "$key")" '.entries[$k] | . != null and (.stage != "settled" and .stage != "closed")' <<<"$doc" >/dev/null && sa_fail "$key already has a thread in the ledger"
    # A repeat keeps the first `since` (how long it has waited is the report's
    # point) and the order and blocker it is not given anew (placement rewrites
    # a row's reason and knows neither).
    row=$(jq -cn --arg k "$key" --arg why "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg order "$order" --arg after "$after" --arg ask "$ask" --arg tr "$trepo" --arg skill "$skill" --argjson place "$place" \
      --argjson old "$(jq -c --arg k "$key" "$sa_jq_norm"'(.waiting // []) | map(select((.key | norm_repo) == ($k | norm_repo))) | first // null' <<<"$doc")" \
      '(if $k | startswith("task:") then {key: $k, repo: (if $tr == "" then null else $tr end), number: null, ask: $ask}
          + (if $skill == "" then {} else {skill: $skill} end) + $place
        else {key: $k, repo: ($k | sub("#[^#]*$"; "")), number: ($k | sub("^.*#"; "") | tonumber)} end)
        + {reason: $why, since: ($old.since // $now),
        order: (if $order != "" then ($order | tonumber) else $old.order end),
        after: (if $after != "" then $after else $old.after end)}')
    sa_update "$ledger" "$sa_jq_norm"'.waiting = ((.waiting // []) | map(select((.key | norm_repo) != ($k | norm_repo))) + [$w])' --arg k "$key" --argjson w "$row"
    jq -cn --argjson w "$row" '{waiting: $w}' ;;
  unwait)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_lock "$ledger"; sa_read "$ledger"
    had=$(jq -r --arg k "$1" "$sa_jq_norm"'[(.waiting // [])[] | select((.key | norm_repo) == ($k | norm_repo))] | length > 0' <<<"$doc")
    [ "$had" != true ] || sa_update "$ledger" "$sa_jq_norm"'.waiting = ((.waiting // []) | map(select((.key | norm_repo) != ($k | norm_repo))))' --arg k "$1"
    jq -cn --arg k "$1" --argjson r "$had" '{key: $k, removed: $r}' ;;
  esac
}
