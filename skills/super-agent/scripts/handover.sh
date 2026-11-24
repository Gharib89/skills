#!/usr/bin/env bash
# The daily handover's one script step: refresh the global super-agent copy when
# it is stale, rewrite the super agent folder's generated settings, then write the
# bearings file the successor thread starts from.
# It reads the ledger and never writes it; stopping the watcher, the schedules,
# the launch and the pin request are the super agent's own steps (SKILL.md's
# Daily handover).
#
#   handover --ledger <file> --from <thread id> --out <file> --projects <file>
#
# The stale check is the one every wake runs (`skill` in pulse and reconcile):
# the loaded copy against the one on Gharib89/skills. Only a loaded copy older
# than the source is refreshed, with `npx skills@1.8.1 add Gharib89/skills
# --skill super-agent --agent claude-code -g -y`; an unread version is no
# verdict, so no refresh. The bearings file is Markdown: the predecessor thread
# (`--from`), the ledger, the skill versions, and one line per open entry, open
# need and waiting row. First it appends the previous day's scorecard row
# (`scorecard row --thread <--from>`), and at the first handover of a week runs
# the weekly review, whose rows join the bearings' Needs you list. A scorecard
# that fails is reported, never a reason to hold the handover. --projects is the
# saved `t3_project_list` answer, or a bare array of the rows of all its pages: the
# successor launches in the project whose workspace is the super agent folder
# (`home.project_id`). Each of these is a Needs you line: a missing project, a guard
# entry the folder's settings lack after the rewrite, a stale guard entry in user
# settings, and user settings that are no JSON object (`home.stale.unreadable`).
#
# stdout: {bearings, skill: {loaded, source, stale}, refreshed, scorecard: {row,
#         error, review, review_error}, home: {folder, settings, written, guard,
#         stale, project_id, needs}}: `bearings` the file written, `refreshed`
#         true when the refresh ran and exited 0, `scorecard.row` the day counted
#         (null when it failed, `error` saying why), `review` the weekly review's
#         rows on the first handover of a week, else null, `review_error` why the
#         review failed (also a Needs you line), else null, `home` the super agent
#         folder (`stale` {settings, entries, unreadable} or null)
# exit: 0 the bearings written · 1 the refresh failed (the bearings still
#       written, saying so) · 2 usage, an unreadable ledger or projects file, or
#       a bearings file that could not be written
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: handover --ledger <file> --from <thread id> --out <file> --projects <file>'
sa_help "$usage" "$@"
ledger='' from='' out='' projects=''
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    --from) sa_flag_value "$usage" "${2:-}"; from=$2 ;;
    --out) sa_flag_value "$usage" "${2:-}"; out=$2 ;;
    --projects) sa_flag_value "$usage" "${2:-}"; projects=$2 ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$ledger" ] && [ -n "$from" ] && [ -n "$out" ] && [ -n "$projects" ] || sa_tooling "$usage"
sa_read "$ledger"
# One page with more after it would miss the folder's project on a later page.
jq -e "$sa_jq_projects"'(project_rows | type == "array") and (type == "array" or .nextCursor == null)' "$projects" >/dev/null 2>&1 \
  || sa_tooling "$projects: not a t3_project_list answer with every page (a nextCursor is set: save all pages' rows as one array)"
# Writable before the refresh, so a refresh never runs for a handover that cannot finish.
{ : >> "$out"; } 2>/dev/null || sa_tooling "cannot write $out"

# One brace group, parsed whole before it runs: the refresh may rewrite this
# very file, and bash reads a script as it goes.
{
# The scorecard before the refresh, so the row is stamped with the version that
# ran the day. The weekly review is reported once per week: `scorecard-reviewed`
# holds the first day of the last week reviewed.
card=$(bash "$(dirname "${BASH_SOURCE[0]}")/scorecard.sh" row --ledger "$ledger" --thread "$from") \
  || printf 'the scorecard row failed: %s\n' "$(jq -r .error <<<"$card" 2>/dev/null)" >&2
review_error=null
review=$(bash "$(dirname "${BASH_SOURCE[0]}")/scorecard.sh" review --ledger "$ledger") \
  || { review_error=$(jq -c '.error // empty' <<<"$review" 2>/dev/null); review_error=${review_error:-'"the review failed"'}
       printf 'the scorecard review failed: %s\n' "$(jq -r . <<<"$review_error")" >&2; review=''; }
mark="$(dirname "$ledger")/scorecard-reviewed" week=''
[ -z "$review" ] || week=$(jq -r .week.from <<<"$review")
[ -n "$week" ] && [ "$(cat "$mark" 2>/dev/null)" != "$week" ] || { review=null week=''; }
scorecard=$(jq -cn --argjson c "${card:-null}" --argjson r "$review" --argjson re "$review_error" \
  '{row: ($c.row.day // null), error: ($c.error // null), review: (if $r == null then null else $r.needs end),
    review_error: $re}')
skill=$(sa_skill_stale)
refreshed=false rc=0
if [ "$(jq -r .stale <<<"$skill")" = true ]; then
  npx skills@1.8.1 add "$sa_skill_source" --skill super-agent --agent claude-code -g -y 2>&1 | tail -n 40 >&2
  if [ "${PIPESTATUS[0]}" -eq 0 ]; then refreshed=true; else rc=1; printf 'the super-agent refresh failed (its output above)\n' >&2; fi
fi

sa_home true "$projects"
jq -r --arg from "$from" --arg l "$ledger" --argjson sk "$skill" --argjson r "$refreshed" --argjson sc "$scorecard" --argjson home "$home" "$sa_jq_open$sa_jq_waiting"'
  def lines($xs): if ($xs | length) == 0 then ["None."] else $xs end;
  ["# Super agent bearings", "",
   "Handed over from thread \($from). Ledger: \($l).", "",
   "Skill: loaded \($sk.loaded // "unread"), source \($sk.source // "unread"), "
     + (if $r then "refreshed to \($sk.source)." elif $sk.stale == true then "stale, the refresh failed." else "no refresh." end), "",
   "## Open entries", ""] + lines([.entries[] | select(is_open) | "- \(.key) thread \(.thread) \(.stage)"])
  + ["", "## Needs you", ""] + lines([((.needs // [])[] | "- \(.key): \(.action)"), (($sc.review // [])[] | "- \(.)"),
      (if $sc.review_error then "- Scorecard: the weekly review failed: \($sc.review_error)" else empty end),
      ($home.needs[] | "- \(.)")])
  + ["", "## Waiting", ""] + lines([waiting_list[] | "- \(.key): \(.reason)"])
  | join("\n")' <<<"$doc" > "$out" || sa_tooling "cannot write $out"
# Marked only once the bearings hold the review's rows.
[ -z "$week" ] || printf '%s\n' "$week" > "$mark" || printf 'cannot write %s\n' "$mark" >&2

jq -cn --arg b "$out" --argjson sk "$skill" --argjson r "$refreshed" --argjson sc "$scorecard" --argjson home "$home" \
  '{bearings: $b, skill: $sk, refreshed: $r, scorecard: $sc, home: $home}'
exit "$rc"
}
