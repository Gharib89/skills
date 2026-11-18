#!/usr/bin/env bash
# The daily handover's one script step: refresh the global super-agent copy when
# it is stale, then write the bearings file the successor thread starts from.
# It reads the ledger and never writes it; stopping the watcher, the schedules,
# the launch and the pin request are the super agent's own steps (SKILL.md's
# Daily handover).
#
#   handover --ledger <file> --from <thread id> --out <file>
#
# The stale check is the one every wake runs (`skill` in pulse and reconcile):
# the loaded copy against the one on Gharib89/skills. Only a loaded copy older
# than the source is refreshed, with `npx skills@1.8.1 add Gharib89/skills
# --skill super-agent --agent claude-code -g -y`; an unread version is no
# verdict, so no refresh. The bearings file is Markdown: the predecessor thread
# (`--from`), the ledger, the skill versions, and one line per open entry, open
# need and waiting row.
#
# stdout: {bearings, skill: {loaded, source, stale}, refreshed}: `bearings` the
#         file written, `refreshed` true when the refresh ran and exited 0
# exit: 0 the bearings written · 1 the refresh failed (the bearings still
#       written, saying so) · 2 usage, an unreadable ledger, or a bearings file
#       that could not be written
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: handover --ledger <file> --from <thread id> --out <file>'
sa_help "$usage" "$@"
ledger='' from='' out=''
while [ $# -gt 0 ]; do
  case $1 in
    --ledger) sa_flag_value "$usage" "${2:-}"; ledger=$2 ;;
    --from) sa_flag_value "$usage" "${2:-}"; from=$2 ;;
    --out) sa_flag_value "$usage" "${2:-}"; out=$2 ;;
    *) sa_tooling "$usage" ;;
  esac
  shift 2
done
[ -n "$ledger" ] && [ -n "$from" ] && [ -n "$out" ] || sa_tooling "$usage"
sa_read "$ledger"

skill=$(sa_skill_stale)
refreshed=false rc=0
if [ "$(jq -r .stale <<<"$skill")" = true ]; then
  if npx skills@1.8.1 add Gharib89/skills --skill super-agent --agent claude-code -g -y >&2; then refreshed=true; else rc=1; fi
fi

jq -r --arg from "$from" --arg l "$ledger" --argjson sk "$skill" --argjson r "$refreshed" "$sa_jq_open$sa_jq_waiting"'
  def lines($xs): if ($xs | length) == 0 then ["None."] else $xs end;
  ["# Super agent bearings", "",
   "Handed over from thread \($from). Ledger: \($l).", "",
   "Skill: loaded \($sk.loaded // "unread"), source \($sk.source // "unread"), "
     + (if $r then "refreshed to \($sk.source)." elif $sk.stale == true then "stale, the refresh failed." else "no refresh." end), "",
   "## Open entries", ""] + lines([.entries[] | select(is_open) | "- \(.key) thread \(.thread) \(.stage)"])
  + ["", "## Needs you", ""] + lines([(.needs // [])[] | "- \(.key): \(.action)"])
  + ["", "## Waiting", ""] + lines([waiting_list[] | "- \(.key): \(.reason)"])
  | join("\n")' <<<"$doc" > "$out" || sa_tooling "cannot write $out"

jq -cn --arg b "$out" --argjson sk "$skill" --argjson r "$refreshed" '{bearings: $b, skill: $sk, refreshed: $r}'
exit "$rc"
