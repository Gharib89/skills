#!/usr/bin/env bash
# Replace one `## <section>` of the PR body with the file's content, creating
# the section at the end when the body has none. Every other line is untouched.
#
#   update-pr-body <pr> --section <name> --body-file <path>
#
# stdout: {pr, section, replaced, created}
# exit: 0 · 1 update failed · 2 usage
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: update-pr-body <pr> --section <name> --body-file <path>'
[ -n "${1:-}" ] || ship_tooling "$usage"
pr=$1; shift
section=""; file=""
while [ $# -gt 0 ]; do
  case $1 in
    --section) [ -n "${2:-}" ] || ship_tooling "$usage"; section=$2; shift 2 ;;
    --body-file) [ -n "${2:-}" ] || ship_tooling "$usage"; file=$2; shift 2 ;;
    *) ship_tooling "unknown flag: $1" ;;
  esac
done
[ -n "$section" ] && [ -f "$file" ] || ship_tooling "$usage"
ship_load_host

body=$(host_pr_get "$pr" | jq -r .body) || ship_tooling "cannot read PR $pr"
new=$(mktemp); trap 'rm -f "$new"' EXIT
if ship_body_replace_section "$body" "$section" "$file" > "$new"; then
  replaced=true; created=false
else
  replaced=false; created=true
fi
host_pr_set_body "$pr" "$new" || ship_fail "PR body update failed"
jq -n --argjson pr "$pr" --arg s "$section" --argjson r "$replaced" --argjson c "$created" \
  '{pr: $pr, section: $s, replaced: $r, created: $c}'
