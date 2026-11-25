#!/usr/bin/env bash
# The scorecard: one row per day counted by `jq` from the ledger and its
# archive, the guard and timer logs, and the pinned thread's transcript, so a
# new super-agent version is judged by counts and not by a model. `row` appends
# a day's row to `scorecard.jsonl` beside the ledger, replacing that day's row
# if one is there; `review` reads a week of rows against the targets.
#
#   scorecard row --ledger <file> [--day <YYYY-MM-DD>] [--thread <id>] [--transcript <file>]... [--version <v>]...
#   scorecard review --ledger <file> [--week <YYYY-MM-DD>] [--targets <file>]
#
# A day is a UTC day, the previous one by default. The transcript is every
# Claude Code transcript (`*.jsonl` under `$CLAUDE_CONFIG_DIR/projects` and
# `~/.claude*/projects`, subagents aside) that names the thread id and loaded
# the super-agent skill: a child's transcript names the id too, in its launch
# message, but never loads this skill. The predecessor that launched the thread
# names it too and counts, so a row is the super agent's whole UTC day, the
# morning before its handover included. The thread id is `--thread`, else the
# ledger's `own_thread`, else `T3CODE_THREAD_ID`; `--transcript` reads the
# files given instead. The row is stamped with `--version`, else the version of
# the copy running this script.
#
# `review` covers the full week (Monday to Sunday, UTC) starting `--week`, by
# default the last full week, against `../scorecard/targets.json`. What each
# number counts, the guard and timer logs' contract (a log not written yet is
# absent, never an error) and when a review raises a row are defined once, in
# `../scorecard/README.md`.
#
# stdout: `row` {row, file}: the row and the file it went to · `review` {week:
#         {from, to}, days, call_guard: {refused}, needs: [text]}: the rows read, the
#         week's call guard refusals, one line per row to raise
# exit: 0 answered · 2 usage, an unreadable ledger, no thread id, no transcript
#       for it, an unread version, a malformed transcript, log, targets or
#       pattern file, a week missing some day's row, or a file that could not
#       be read or written
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: scorecard row --ledger <file> [--day <YYYY-MM-DD>] [--thread <id>] [--transcript <file>]... [--version <v>]... | scorecard review --ledger <file> [--week <YYYY-MM-DD>] [--targets <file>]'
sa_help "$usage" "$@"
data="$(dirname "${BASH_SOURCE[0]}")/../scorecard"
cmd=${1:-}; shift || true
ledger='' day='' thread='' week='' targets="$data/targets.json" files=() versions=()
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    --day) sa_flag_value "$usage" "${2:-}"; day=$2 ;;
    --week) sa_flag_value "$usage" "${2:-}"; week=$2 ;;
    --thread) sa_flag_value "$usage" "${2:-}"; thread=$2 ;;
    --transcript) sa_flag_value "$usage" "${2:-}"; files+=("$2") ;;
    --version) sa_flag_value "$usage" "${2:-}"; versions+=("$2") ;;
    --targets) sa_flag_value "$usage" "${2:-}"; targets=$2 ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
case $cmd in row|review) ;; *) sa_tooling "$usage" ;; esac
[ -n "$ledger" ] || sa_tooling "$usage"
for d in "$day" "$week"; do
  [ -z "$d" ] || [ "$(jq -rn --arg d "$d" 'try ($d | strptime("%Y-%m-%d") | mktime | strftime("%Y-%m-%d")) catch ""')" = "$d" ] \
    || sa_tooling "$d: not a calendar day, YYYY-MM-DD"
done
sa_read "$ledger"
dir=$(dirname "$ledger") card="$(dirname "$ledger")/scorecard.jsonl"
now=$(sa_now_s)

if [ "$cmd" = review ]; then
  [ -f "$targets" ] && jq -e 'type == "object" and all(.[]; type == "object" and (.max | type) == "number")' "$targets" >/dev/null 2>&1 \
    || sa_tooling "$targets: not a targets file, {<path>: {max: <number>}}"
  # The Monday of the week `$now` falls in, less 7 days: the last full week.
  [ -n "$week" ] || week=$(jq -rn --argjson n "$now" '($n - ($n | strftime("%u") | tonumber) * 86400 - 6 * 86400) | strftime("%Y-%m-%d")')
  rows='[]'
  [ -f "$card" ] && { rows=$(jq -sc . "$card" 2>/dev/null) || sa_tooling "$card: not JSON lines"; }
  jq -c --arg w "$week" --slurpfile t "$targets" '
    def day($d): $d | strptime("%Y-%m-%d") | mktime;
    def at($p): getpath($p | split("."));
    . as $rows | (day($w)) as $from | ($from + 6 * 86400 | strftime("%Y-%m-%d")) as $to
    | ($from - 21 * 86400 | strftime("%Y-%m-%d")) as $four
    | (map(select(.day >= $w and .day <= $to)) | unique_by(.day)) as $days
    | ([range(7) | $from + . * 86400 | strftime("%Y-%m-%d")] - [$days[].day]) as $missing
    # A week with no row at all predates the scorecard: nothing to review.
    | if $missing != [] and $days != [] then error("week \($w): no row for \($missing | join(", ")); count it with row --day") else . end
    | {week: {from: $w, to: $to}, days: ($days | length),
       call_guard: {refused: ([$days[] | .call_guard.refused? // 0] | add // 0)}, needs: (
        [$t[0] | to_entries[] | select(.value.slice == null) | .key as $k | .value.max as $max
          | [$days[] | at($k) | select(type == "number" and . > $max)] as $over
          | select($over | length > 0)
          | "Scorecard: \($k) missed its target of \($max) on \($over | length) of \($days | length) days (worst \($over | max))."]
        + [[$rows[] | .guards // {} | keys[]] | unique[] as $g
          | [$rows[] | select(.guards[$g] != null)] as $seen
          | [$seen[] | select(.day >= $four and .day <= $to)] as $in
          # Logged in each of the four weeks, and no block in them.
          | select(($seen | map(.day) | min) <= $four and all(range(4) as $k | ($from - (21 - 7 * $k) * 86400 | strftime("%Y-%m-%d")) as $a
                  | ($from - (15 - 7 * $k) * 86400 | strftime("%Y-%m-%d")) as $b
                  | any($in[]; .day >= $a and .day <= $b); .)
              and ([$in[] | .guards[$g].blocks] | add // 0) == 0)
          | "Scorecard: the \($g) guard blocked nothing for four weeks; delete it?"]
        + [$days[] | .questions.turns[]? | "Scorecard: the owner question at \(.at) (prompt \(.prompt_id)) held a changing call: \(.calls | map(.tool) | unique | join(", ")); read the turn and take its sender from t3_thread_read."])}' <<<"$rows" 2>"$dir/.scorecard-review.err" \
    || { e=$(sed -n 's/^jq: error ([^)]*): //p' "$dir/.scorecard-review.err" | head -n 1); rm -f "$dir/.scorecard-review.err"; sa_tooling "review failed: ${e:-jq error}"; }
  rm -f "$dir/.scorecard-review.err"
  exit 0
fi

# --- row ---------------------------------------------------------------------
[ -n "$day" ] || day=$(jq -rn --argjson n "$now" '$n - 86400 | strftime("%Y-%m-%d")')
if [ ${#versions[@]} -eq 0 ]; then
  v=$(jq -Rsr "$sa_jq_ver"'skill_version' "$(dirname "${BASH_SOURCE[0]}")/../SKILL.md" 2>/dev/null)
  [ -n "$v" ] || sa_tooling "the running copy's version is unread: pass --version"
  versions=("$v")
fi
if [ ${#files[@]} -eq 0 ]; then
  [ -n "$thread" ] || thread=$(jq -r '.own_thread // empty' <<<"$doc")
  [ -n "$thread" ] || thread=${T3CODE_THREAD_ID:-}
  [ -n "$thread" ] || sa_tooling "no thread id: pass --thread, or run in the super agent's thread"
  roots=()
  for r in "${CLAUDE_CONFIG_DIR:-}" "$HOME"/.claude*; do [ -n "$r" ] && [ -d "$r/projects" ] && roots+=("$r/projects"); done
  if [ ${#roots[@]} -gt 0 ]; then
    while IFS= read -r f; do
      case $f in */subagents/*) continue ;; esac
      # A skill load is a user entry that opens on the line; a session that only
      # quotes the line, in a command or its output, never loaded the skill.
      grep -qF 'Base directory for this skill: ' "$f" && jq -enR 'first(inputs | fromjson? // empty
        | select(type == "object" and .type == "user" and (.isSidechain | not)) | .message.content
        | if type == "array" then .[]? | .text? else . end | strings
        | select(test("^Base directory for this skill: \\S*/super-agent(\\s|$)"))) | true' "$f" >/dev/null 2>&1 \
        && files+=("$f")
    done < <(grep -rlF --include='*.jsonl' -- "$thread" "${roots[@]}" 2>/dev/null | sort -u)
  fi
  [ ${#files[@]} -gt 0 ] || sa_tooling "no transcript for thread $thread: none under ~/.claude*/projects loaded the super-agent skill"
fi
for f in ${files[@]+"${files[@]}"}; do [ -r "$f" ] || sa_tooling "$f: cannot read"; done
patterns=$(jq -Rsr 'split("\n") | map(select(length > 0 and (startswith("#") | not))) | join("|")' "$data/nothing-changed.txt") \
  || sa_tooling "$data/nothing-changed.txt: cannot read"
[ -n "$patterns" ] && jq -n --arg p "$patterns" '"" | test($p)' >/dev/null 2>&1 \
  || sa_tooling "$data/nothing-changed.txt: no pattern, or one that is no regex"
[ ! -f "$ledger.archive.jsonl" ] || jq -s . "$ledger.archive.jsonl" >/dev/null 2>&1 || sa_tooling "$ledger.archive.jsonl: not JSON lines"

source "$(dirname "${BASH_SOURCE[0]}")/scorecard.d/logs.sh" || sa_tooling "cannot source scorecard.d/logs.sh"

# One slim record per transcript entry, file by file in order, so a 30 MB
# transcript is never held whole: a user entry's text (null for a tool result),
# an assistant entry's usage, texts and tool calls.
slim=$(for i in ${files[@]+"${!files[@]}"}; do
  jq -cR --argjson f "$i" 'fromjson? // empty | select(type == "object" and (.isSidechain | not))
    | if .type == "user" then (.message.content) as $c
      | {f: $f, ts: .timestamp, u: true, origin: (.origin.kind? // null),
         skip: ((.isCompactSummary // false) or (.isMeta // false)),
         text: (if ($c | type) == "string" then $c
           elif ($c | type) == "array" then (if any($c[]; .type? == "tool_result") then null
             else [$c[] | select(.type? == "text") | .text] | join(" ") end)
           else null end)}
    elif .type == "assistant" and .message.model != "<synthetic>" then .message as $m
      | {f: $f, ts: .timestamp, id: $m.id,
         use: ($m.usage // {} | {in: (.input_tokens // 0), cw: (.cache_creation_input_tokens // 0),
           cr: (.cache_read_input_tokens // 0), out: (.output_tokens // 0)}),
         texts: [$m.content[]? | select(.type == "text") | .text],
         tools: [$m.content[]? | select(.type == "tool_use")
           | {name, id, cmd: (.input.command? // null), bg: (.input.run_in_background? // false)}]}
    else empty end' "${files[$i]}" || exit 1
done | jq -sc .) || sa_tooling "cannot read the transcripts"

row=$(jq -c --arg day "$day" --argjson v "$(printf '%s\n' "${versions[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
  --arg thread "${thread:-}" --arg nc "$patterns" --argjson logs "$logs" --argjson timer "$timer" --argjson qlog "$qlog" --argjson cglog "$cglog" --argjson nlog "$nlog" \
  --slurpfile led <(printf '%s\n' "$doc") --slurpfile archive <(cat "$ledger.archive.jsonl" 2>/dev/null) "$sa_jq_norm$sa_jq_open$sa_jq_changing"'
  def wsum: reduce .[] as $t ({in: 0, cw: 0, cr: 0, out: 0}; .in += $t.in | .cw += $t.cw | .cr += $t.cr | .out += $t.out);
  def total: .in + .cw + .cr + .out;
  def weighted: .in + 2 * .cw + 0.1 * .cr + 5 * .out;
  def median: sort | length as $n | if $n == 0 then null elif $n % 2 == 1 then .[($n - 1) / 2]
    else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
  def per($n): if $n > 0 then (. / $n * 100 | round) / 100 else null end;
  # Every script or tool that changes state (`lib/changing.sh` holds the ledger and
  # host patterns): one this list misses counts as changing nothing.
  def changing_bash: [ledger_write(ledger_verbs), "reply\\.sh"] + acting_scripts + host_writes
    + ["chezmoi\\s+apply", "npx\\s+skills"] | join("|");
  def changing_tools: ["mcp__t3-code__t3_thread_launch", "mcp__t3-code__t3_thread_send", "mcp__t3-code__t3_thread_organize",
    "AskUserQuestion", "PushNotification", "mcp__t3-code__t3_thread_interrupt", "mcp__t3-code__t3_thread_configure",
    "mcp__t3-code__schedule_task", "mcp__t3-code__delete_scheduled_task", "mcp__t3-code__delegate_task",
    "mcp__t3-code__link_pull_request", "Write", "Edit", "Agent", "Artifact"];
  def boiler: ["<local-command-", "<command-name>/compact", "<command-name>/reload-skills", "<command-name>/model",
    "This session is being continued", "Base directory for this skill", "[Image:", "<system-reminder>",
    "(Re-invocation of"] as $p | . as $t | any($p[]; . as $q | $t | startswith($q));
  # What woke a turn, from its trimmed text, the background commands started so
  # far ($bg: tool-use id to command) and the entry origin kind ($o).
  def cause($bg; $o): . as $t
    | if $t | startswith("<task-notification>") then
        (($t | capture("<tool-use-id>(?<id>.*?)</tool-use-id>").id // null) as $id | ($bg[$id // ""] // "")) as $c
        | if ($c | test("watch(-fired|-thread|-\\d+)?\\.sh")) or ($t[0:400] | test("watch"; "i")) then "watcher" else "other background" end
      elif $t | startswith("[T3 Code:") then
        if ($t[0:60] | contains("scheduled task") | not) then "other"
        elif ($t | contains("Backstop:")) or ($t | contains("Wake: reconcile")) then "backstop" else "other scheduled" end
      elif ($t | startswith("Wake: reconcile")) or ($t | startswith("Backstop:")) then "backstop"
      elif ($t | startswith("Morning report")) or ($t | startswith("Wake:")) or ($t | startswith("Quota launch wake")) then "other scheduled"
      elif $o == "plugin" or ($t | startswith("The smart-compact plugin")) then "compaction resume"
      elif $o == "peer" or ($t | startswith("Another Claude session")) then "other"
      elif ($t | startswith("Note: the T3 server restarted")) or ($t | startswith("[Your previous response"))
        or ($t | startswith("Continue where you left off")) then "restart or harness"
      else "owner" end;
  # The wakes of one transcript: a wake is a turn start (a user entry that is no
  # tool result and no boilerplate) and runs to the next. Tokens are summed once
  # per API call: a message id seen again replaces its earlier usage.
  def wakes: reduce .[] as $e ({w: [], bg: {}, seen: {}};
    if $e.u then ($e.text // "" | sub("^\\s+"; "")) as $t
      | if $e.text == null or $e.skip or ($t | boiler) then .
      else .bg as $bg | .w += [{ts: $e.ts, cause: ($t | cause($bg; $e.origin)), text: $t,
        tok: {in: 0, cw: 0, cr: 0, out: 0}, api: 0, changed: false}] end
    elif (.w | length) == 0 then .
    else (.w | length - 1) as $cur | .seen[$e.id] as $prev | ($prev.w // $cur) as $own
      | (if $prev then .w[$own].tok |= with_entries(.value -= $prev.use[.key]) else .w[$cur].api += 1 end)
      | .w[$own].tok |= with_entries(.value += $e.use[.key])
      | .seen[$e.id] = {w: $own, use: $e.use}
      | reduce $e.tools[] as $t (.;
          (if $t.name == "Bash" and $t.bg then .bg[$t.id] = $t.cmd else . end)
          | if ($t.name == "Bash" and (($t.cmd // "") | test(changing_bash))) or ($t.name | IN(changing_tools[]))
            then .w[$cur].changed = true else . end)
    end) | .w;
  . as $all
  | [group_by(.f)[] | wakes[]] | map(select(.api > 0 and (.ts // "" | startswith($day)))) as $wakes
  | [$all[] | select(.u | not) | select(.ts // "" | startswith($day))] as $calls
  | [$calls[] | .texts[] | select(length > 0)] as $msgs
  | [$calls[] | .tools[] | select(.name == "Bash") | .cmd // ""] as $cmds
  | ($nlog // []) as $nl
  | def today($ev): [$nl | to_entries[] | select(.value.event == $ev and (.value.at // "" | startswith($day)))];
    def again($ev): [today($ev)[] | .key as $i | .value as $x
      | select(any($nl[:$i][]; .event == $ev and (.key | norm_repo) == ($x.key | norm_repo) and .action == $x.action))] | length;
  ($day | strptime("%Y-%m-%d") | mktime) as $d0 | ($d0 + 86400) as $d1
  | ([$led[0].entries[]] + $archive) as $ents
  | def ended: (.settled_at // (if is_open then null else .updated_at end));
    def epoch: if . == null then null else sub("[.][0-9]+"; "") | fromdateiso8601 end;
    ([$ents[] | select((.launched_at | epoch) as $a | $a != null and $a < $d1)
      | select((ended | epoch) as $e | $e == null or $e >= $d0)] | length) as $open
  | ([$ents[] | select((ended | epoch) as $e | $e != null and $e >= $d0 and $e < $d1)] | length) as $settled
  | ($wakes | map(.tok) | wsum) as $tok
  | ($wakes | map(select(.changed | not) | .tok) | wsum) as $nctok
  | def guard: {blocks: map(select(.event == "block" and (.at // "" | startswith($day)))) | length,
      passes: map(select(.event == "pass" and (.at // "" | startswith($day)))) | length};
  {day: $day, versions: $v, thread: (if $thread == "" then null else $thread end),
   workload: {open: $open, settled: $settled},
   messages: {count: ($msgs | length), per_open: ($msgs | length | per($open)),
     nothing_changed: ([$msgs[] | select(test($nc; "i"))] | length),
     over_1500: ([$msgs[] | select(length > 1500)] | length), median_chars: ($msgs | map(length) | median)},
   needs: {recorded: ([$cmds[] | select(test("ledger\\.sh[^|;&\\n]*?\\sneed\\s"))] | length),
     alerted: (today("alert") | length), alerted_twice: (again("alert") + again("reminder"))},
   guards: (if $logs == {} then null else $logs | map_values(guard) end),
   call_guard: (if $cglog == null then null
     else {refused: ([$cglog[] | select(.event == "refused" and (.at // "" | startswith($day)))] | length),
       told: ([$cglog[] | select(.event == "told" and (.at // "" | startswith($day)))] | length)} end),
   timer: (if $timer == null then null
     else [$timer[] | select(.event == "closed" and (.at // "" | startswith($day))) | .minutes] as $m
       | {outages: ($m | length), median_minutes: ($m | median), worst_minutes: ($m | max)} end),
   questions: (if $qlog == null then null
     else [$qlog[] | select(.event == "changing")] as $ch
       | [$qlog[] | select(.event == "flag" and (.at // "" | startswith($day)))] as $fl
       | ($fl | map(. as $f | {prompt_id, at, calls: [$ch[] | select(.prompt_id == $f.prompt_id) | {tool, call}]})
           | map(select(.calls | length > 0))) as $turns
       | {asked: ($fl | length), with_write: ($turns | length), turns: $turns} end),
   wakes: {count: ($wakes | length), per_open: ($wakes | length | per($open)),
     by_cause: ($wakes | group_by(.cause) | map({key: .[0].cause, value: length}) | from_entries),
     changed_nothing: ($wakes | map(select(.changed | not)) | length)},
   tokens: {total: ($tok | total), weighted: ($tok | weighted | round), per_open: ($tok | weighted | per($open)),
     nothing_changed_share: (if ($tok | weighted) > 0 then (($nctok | weighted) / ($tok | weighted) * 100 | round) / 100 else null end)}}
  ' <<<"$slim") || sa_tooling "cannot count the row for $day"

# Replace the day's row, or append it; rows that do not parse are never dropped.
[ ! -f "$card" ] || jq -s . "$card" >/dev/null 2>&1 || sa_tooling "$card: not JSON lines"
mkdir -p "$dir" || sa_tooling "cannot create $dir"
trap 'rm -f "${tmp:-}"' EXIT
tmp=$(mktemp "$dir/.scorecard.XXXXXX") || sa_tooling "cannot write in $dir"
{ [ -f "$card" ] && jq -c --arg d "$day" 'select(.day != $d)' "$card"; printf '%s\n' "$row"; } > "$tmp" && mv "$tmp" "$card" \
  || sa_tooling "cannot write $card"
jq -cn --argjson r "$row" --arg f "$card" '{row: $r, file: $f}'
