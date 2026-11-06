#!/usr/bin/env bash
# Edit the fleet file's active repos, the only repos the daily offer scans:
# "track <repo>" adds one and "stop tracking <repo>" removes one. Everything
# else in the file keeps its value, and a write is a temp file then a rename.
#
#   track --fleet <file> track <owner/name>
#   track --fleet <file> stop <owner/name>
#
# The file is the one `setup --write` made; a missing file is refused rather
# than created, since the machines and waivers a fresh one lacks are setup's to
# propose. A repo name is compared without regard to case, as GitHub does.
# Tracking a repo already tracked, or stopping one that is not, changes
# nothing and says so.
#
# stdout: {fleet_file, action, repo, changed, active_repos}: `active_repos` the
#         list as the file now holds it, in the order tracked
# exit: 0 done, `changed` false when the file already said so · 2 usage, a
#       fleet file that is missing, not JSON or has `active_repos` of the wrong
#       shape, or a write that failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: track --fleet <file> (track | stop) <owner/name>'
sa_help "$usage" "$@"
[ "${1:-}" = --fleet ] || sa_tooling "$usage"
sa_flag_value "$usage" "${2:-}"
fleet=$2; shift 2
[ $# -eq 2 ] || sa_tooling "$usage"
action=$1 repo=$2
case $action in track|stop) ;; *) sa_tooling "$usage" ;; esac
case $repo in */*/*|*/|/*|*[!A-Za-z0-9._/-]*) sa_tooling "$usage" ;; */*) ;; *) sa_tooling "$usage" ;; esac
[ -f "$fleet" ] || sa_tooling "$fleet: no such file (run setup first)"
jq -e 'type == "object"' "$fleet" >/dev/null 2>&1 || sa_tooling "$fleet: not a JSON object"
jq -e '(.active_repos // []) | type == "array" and all(type == "string")' "$fleet" >/dev/null \
  || sa_tooling "$fleet: active_repos must be an array of strings"

new=$(jq -c --arg r "$repo" --arg a "$action" '
  ($r | ascii_downcase) as $l
  | (.active_repos // []) as $old
  | .active_repos = (if $a == "track" then ($old + (if $old | map(ascii_downcase) | index($l) then [] else [$r] end))
                     else ($old | map(select(ascii_downcase != $l))) end)' "$fleet")
changed=$(jq -n --slurpfile o "$fleet" --argjson n "$new" '($o[0].active_repos // []) != $n.active_repos')
[ "$changed" = false ] || sa_write "$fleet" "$new"
jq -cn --arg f "$fleet" --arg a "$action" --arg r "$repo" --argjson c "$changed" --argjson n "$new" \
  '{fleet_file: $f, action: $a, repo: $r, changed: $c, active_repos: $n.active_repos}'
