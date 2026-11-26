# The owner's needs and acknowledge marks: the arms of `ledger` that `need`, `unneed`,
# `ack` and `answer` take, sourced by it. They read the caller's $usage, $ledger and
# $doc, which `ledger.sh` sets.

# shellcheck disable=SC2154  # usage, ledger, sa_jq_norm and sa_jq_needs come from ledger.sh and _lib.sh

# need_class_of <word>: the word's class, or a refusal naming the words the table holds.
need_class_of() {
  local c
  c=$(jq -rn --arg w "$1" "$sa_jq_norm$sa_jq_needs"'$w | need_class // empty')
  [ -n "$c" ] || sa_tooling "$1: not a need reason word; one of $(jq -rn "$sa_jq_norm$sa_jq_needs"'need_classes | keys_unsorted | join(" ")')"
  printf '%s' "$c"
}

ledger_needs() {
  local cmd=$1 key action='' reason='' why='' answer_in='' class row had text n opt entry stage now
  local options=()
  shift
  case $cmd in
  need)
    [ $# -ge 1 ] || sa_tooling "$usage"
    key=$1; shift
    while [ $# -gt 0 ]; do
      sa_flag_value "$usage" "${2:-}"
      case $1 in
        --action) action=$2 ;;
        --reason) reason=$2 ;;
        --why) why=$2 ;;
        --option) options+=("$2") ;;
        --answer-in) answer_in=$2 ;;
        *) sa_tooling "$usage" ;;
      esac
      shift 2
    done
    case $key in task:?*) ;; */*#*[0-9]) case ${key##*#} in *[!0-9]*) sa_tooling "$usage" ;; esac ;; *) sa_tooling "$usage" ;; esac
    [ -n "$action" ] && [ -n "$reason" ] && [ -n "$why" ] || sa_tooling "a need takes --action, --reason and --why"
    class=$(need_class_of "$reason") || { printf '%s\n' "$class"; exit 2; }
    for text in "$action" "$why" ${options[@]+"${options[@]}"}; do
      case $text in *$'\n'*) sa_tooling "an action, a why and an option are one line each" ;; esac
    done
    # The limits that keep the needs-you message legible: `Offer: <action>?` within 80
    # characters, the verb and ticket within the 30 a collapsed phone title shows.
    [ ${#action} -le 72 ] || sa_tooling "the action is ${#action} characters; at most 72"
    [[ $action =~ ^([^[:space:]]+)\ (task:[^[:space:]]+|([^/#[:space:]]+/)?[^/#[:space:]]+#[0-9]+)([[:space:]?]|$) ]] \
      || sa_tooling "the action reads verb, ticket, detail: its second word is the ticket (name#n, owner/name#n or task:slug)"
    n=$(( ${#BASH_REMATCH[1]} + 1 + ${#BASH_REMATCH[2]} ))
    [ "$n" -le 30 ] || sa_tooling "the verb and ticket end at character $n; at most 30"
    if [ -n "$answer_in" ]; then
      [ ${#options[@]} -eq 0 ] || sa_tooling "a need answered in its own thread (--answer-in) takes no options"
    else
      [ ${#options[@]} -ge 2 ] && [ ${#options[@]} -le 4 ] || sa_tooling "a need takes 2 to 4 options, or --answer-in"
    fi
    for opt in ${options[@]+"${options[@]}"}; do
      text=${opt%%: *}
      [ -n "$text" ] && [ "$(wc -w <<<"$text")" -le 5 ] || sa_tooling "an option's label is 1 to 5 words: $text"
    done
    sa_lock "$ledger"; sa_read "$ledger"
    now=$(jq -rn --argjson s "$(sa_now_s)" '$s | todate')
    # A repeat of an open need's action keeps its time and its alert and reminder marks,
    # whatever its reason word: the owner was told of that action once. So does a need
    # recorded before `--why` on the same key, whose free-text action the owner was
    # told of and which a ticket-led action replaces.
    row=$(jq -cn --arg k "$key" --arg a "$action" --arg r "$reason" --arg c "$class" --arg why "$why" --arg in "$answer_in" --arg now "$now" \
      --argjson opts "$(printf '%s\n' ${options[@]+"${options[@]}"} | jq -Rc 'select(length > 0) | capture("^(?<label>.*?): (?<consequence>.*)$") // {label: ., consequence: null}' | jq -sc .)" \
      --argjson old "$(jq -c --arg k "$key" "$sa_jq_norm"'(.needs // []) | map(select((.key | norm_repo) == ($k | norm_repo))) | first // null' <<<"$doc")" \
      "$sa_jq_norm$sa_jq_needs"'{key: $k, action: $a, reason: $r, class: $c, why: $why, options: $opts, answer_in: (if $in == "" then null else $in end),
        since: $now, alerted: null, reminded: null}
       + (if $old != null and ($old.action == $a or $old.why == null) then {since: $old.since, alerted: ($old | need_alerted), reminded: ($old.reminded // null)} else {} end)')
    sa_update "$ledger" "$sa_jq_norm"'.needs = ((.needs // []) | map(select((.key | norm_repo) != ($k | norm_repo))) + [$n])' --arg k "$key" --argjson n "$row"
    jq -cn --argjson n "$row" '{need: $n}' ;;
  unneed)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_lock "$ledger"; sa_read "$ledger"
    had=$(jq -r --arg k "$1" "$sa_jq_norm"'[(.needs // [])[] | select((.key | norm_repo) == ($k | norm_repo))] | length > 0' <<<"$doc")
    [ "$had" != true ] || sa_update "$ledger" "$sa_jq_norm"'.needs = ((.needs // []) | map(select((.key | norm_repo) != ($k | norm_repo))))' --arg k "$1"
    jq -cn --arg k "$1" --argjson r "$had" '{key: $k, removed: $r}' ;;
  ack)
    [ $# -eq 3 ] && [ "$2" = --reason ] || sa_tooling "$usage"
    sa_flag_value "$usage" "$3"; reason=$3
    class=$(need_class_of "$reason") || { printf '%s\n' "$class"; exit 2; }
    sa_lock "$ledger"; sa_read "$ledger"
    key=$(sa_key "$doc" "$1")
    entry=$(jq -c --arg k "$key" '.entries[$k] // empty' <<<"$doc")
    [ -n "$entry" ] || sa_fail "$1 is not in the ledger"
    stage=$(jq -r .stage <<<"$entry")
    now=$(jq -rn --argjson s "$(sa_now_s)" '$s | todate')
    row=$(jq -cn --arg k "$key" --arg r "$reason" --arg s "$stage" --arg now "$now" '{key: $k, reason: $r, stage: $s, since: $now}')
    sa_update "$ledger" "$sa_jq_norm"'.acks = ([(.acks // [])[] | select((.key | norm_repo) != ($k | norm_repo) or .reason != $r)] + [$a])' --arg k "$key" --arg r "$reason" --argjson a "$row"
    jq -cn --argjson a "$row" '{ack: $a}' ;;
  answer)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_read "$ledger"
    jq -e '(.needs // []) | type == "array" and all(type == "object" and (.key | type) == "string" and (.action | type) == "string" and ((.options // []) | type) == "array")' <<<"$doc" >/dev/null \
      || sa_tooling "$ledger: needs are not the shape answer reads"
    # `<ticket> <option>` or a bare `<option>`; the ticket is a number, name#n, owner/name#n
    # or task:slug, matched against the need's key and the ticket its action names.
    text=$(jq -c --arg t "$1" "$sa_jq_norm$sa_jq_needs"'
      def tickets: [.key, need_ticket] | map(norm_repo);
      def num: if test("#[0-9]+$") then sub("^.*#"; "") else null end;
      try ((($t | norm_repo | capture("^\\s*((?<who>\\S+)\\s+)?(?<opt>[0-9]+)\\s*$")) as $m
      | [(.needs // [])[] | select((.options // []) | length > 0)] as $open
      | (if $m.who == null then
           if ($open | length) == 1 then $open else error("a bare number counts only while exactly one need with options is open; \($open | length) are: answer <ticket> <option>") end
         else [$open[] | select(tickets as $ks | any($ks[]; . == $m.who or num == $m.who or (endswith("/" + $m.who))))] end) as $hit
      | if ($hit | length) != 1 then error("\($m.who) names \($hit | length) open needs with options; name the ticket as owner/name#n")
        else $hit[0] as $n | ($m.opt | tonumber) as $o
        | if $o < 1 or $o > ($n.options | length) then error("\($n.key) has options 1 to \($n.options | length)")
          else {key: $n.key, action: $n.action, option: $o, label: $n.options[$o - 1].label, consequence: $n.options[$o - 1].consequence} end end)
        // {error: "\($t): not a reply to an open need, <ticket> <option>"}) catch {error: .}' <<<"$doc")
    [ -n "$text" ] || sa_tooling "answer: jq failed reading $ledger"
    jq -e 'has("error")' <<<"$text" >/dev/null && sa_fail "$(jq -r .error <<<"$text")"
    printf '%s\n' "$text" ;;
  esac
}
