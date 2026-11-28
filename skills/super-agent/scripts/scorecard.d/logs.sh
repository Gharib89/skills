# The logs beside the ledger that `scorecard row` counts, read and checked once, sourced by
# it: the guards' (`<name>-guard.jsonl`), the call guard's, the wake timer's, the question
# flag's, the needs' alerts (`status`) and the watcher's linked-machine log. A log not
# written yet is null; one with a line that is no JSON is refused by name. They read the
# caller's $dir and set $logs, $cglog, $timer, $qlog, $nlog and $rlog.

# shellcheck disable=SC2154,SC2034  # dir comes from scorecard.sh; logs, cglog, timer, qlog, nlog and rlog are read there
# A guard log is `<name>-guard.jsonl`; its name is the row's key under `guards`.
logs='{}'
for g in "$dir"/*-guard.jsonl; do
  # the call guard logs refusals and told sends, not blocks and passes: its own row below
  [ -f "$g" ] || continue
  [ "$g" != "$dir/call-guard.jsonl" ] || continue
  n=$(basename "$g" -guard.jsonl)
  e=$(jq -sc . "$g" 2>/dev/null) || sa_tooling "$g: not JSON lines"
  logs=$(jq -c --arg n "$n" --argjson e "$e" '.[$n] = $e' <<<"$logs")
done
cglog=null
if [ -f "$dir/call-guard.jsonl" ]; then cglog=$(jq -sc . "$dir/call-guard.jsonl" 2>/dev/null) || sa_tooling "$dir/call-guard.jsonl: not JSON lines"; fi
nlog=null
if [ -f "$dir/needs-alerts.jsonl" ]; then nlog=$(jq -sc . "$dir/needs-alerts.jsonl" 2>/dev/null) || sa_tooling "$dir/needs-alerts.jsonl: not JSON lines"; fi
timer=null
if [ -f "$dir/wake-timer.jsonl" ]; then timer=$(jq -sc . "$dir/wake-timer.jsonl" 2>/dev/null) || sa_tooling "$dir/wake-timer.jsonl: not JSON lines"; fi
rlog=null
if [ -f "$dir/remote-watch.jsonl" ]; then rlog=$(jq -sc . "$dir/remote-watch.jsonl" 2>/dev/null) || sa_tooling "$dir/remote-watch.jsonl: not JSON lines"; fi
qlog=null
if [ -f "$dir/question-flag.jsonl" ]; then qlog=$(jq -sc . "$dir/question-flag.jsonl" 2>/dev/null) || sa_tooling "$dir/question-flag.jsonl: not JSON lines"
  bad=$(jq -r 'map(select((type == "object" and (.at | type) == "string" and (.event | type) == "string"
      and (if .event == "flag" then (.prompt_id | type) == "string"
        elif .event == "changing" then (.prompt_id | type) == "string" and (.tool | type) == "string"
        else true end)) | not)) | length' <<<"$qlog")
  [ "$bad" = 0 ] || sa_tooling "$dir/question-flag.jsonl: $bad record(s) lack a string at and event, or a flag or changing record lacks its prompt_id or tool"
fi
