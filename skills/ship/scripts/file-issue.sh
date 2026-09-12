#!/usr/bin/env bash
# File an adjacent find for triage and leave it alone, unless the tracker
# already carries it.
#
#   file-issue --title "<title>" --body-file <path> --label <triage marker>
#              [--distinct-from <n>[,<n>]]
#
# Duplicate check. Before creating, the mechanic lists the host's open issues
# and compares titles: lowercased, punctuation as a separator, tokens under
# four characters and generic English stopwords dropped. An open issue sharing
# three or more tokens with the new title is a candidate, and with any
# candidate the mechanic files nothing, so consecutive runs meeting the same
# adjacent find cannot file it twice. `--distinct-from` names the numbers the
# caller has read and judged different, and files past them.
#
# The list is the host's own, and GitHub's serves a just-created issue a few
# seconds late, so two calls seconds apart can both file. That is the caller's
# to handle and cheap to: one run already knows what it just filed, and the
# check is for the same find met by a later run, minutes or days on.
#
# stdout: {"filed": true, "number": <n>, "url": "<url>"}
#         {"filed": false, "candidates": [{number, title, url}]}
# exit: 0 filed, or a candidate found · 1 list or create failed · 2 usage
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

# Generic English function words of four or more characters; shorter ones the
# length rule already drops. No repo-specific word belongs here: the mechanic
# is generic, and an over-eager candidate costs one `--distinct-from` while a
# missed one costs a duplicate issue.
STOPWORDS='about also been both does each else from have here into just like made make more most much must only over same some such than that them then they this those very were what when will with would your'

title=""; file=""; label=""; exclude="[]"
while [ $# -gt 0 ]; do
  case $1 in
    --title) title=${2:?}; shift 2 ;;
    --body-file) file=${2:?}; shift 2 ;;
    --label) label=${2:?}; shift 2 ;;
    --distinct-from)
      exclude=$(jq -cn --arg n "${2:?}" '$n | split(",") | map(tonumber)' 2>/dev/null) \
        || ship_tooling "--distinct-from takes issue numbers: $2"
      shift 2 ;;
    *) ship_tooling "unknown flag: $1" ;;
  esac
done
[ -n "$title" ] && [ -f "$file" ] || ship_tooling 'usage: file-issue --title "<title>" --body-file <path> --label <marker> [--distinct-from <n>[,<n>]]'
ship_load_host

open=$(host_issues_open) || ship_fail "cannot list open issues"
candidates=$(jq -c --arg t "$title" --argjson x "$exclude" --arg s "$STOPWORDS" '
  def tokens: ascii_downcase | [splits("[^a-z0-9]+")]
    | map(select(length >= 4)) | unique | . - ($s | split(" "));
  ($t | tokens) as $new
  | [ .[]
      | select(([.number] - $x) != [])
      | select((($new - ($new - (.title | tokens))) | length) >= 3)
      | {number, title, url} ]' <<<"$open") || ship_fail "candidate check failed"
if [ "$candidates" != "[]" ]; then
  jq -n --argjson c "$candidates" '{filed: false, candidates: $c}'
  exit 0
fi

out=$(host_issue_create "$title" "$file" "$label") || ship_fail "issue create failed"
jq '{filed: true} + .' <<<"$out"
