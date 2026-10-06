#!/usr/bin/env bash
# ship phases 6 and 7: the PR in one normalized payload, the read-back after a
# title or body write.
#
#   read-pr <pr>
#
# stdout: {number, url, title, body, head_sha, head_ref, base_ref, draft,
#          state, mergeable, headings[], missing[]}
#   The adapter's PR object: the same fields on both hosts. Comments, review
#   threads and checks come from poll-pr. headings: the body's `## ` section
#   headings, in order (the rule `update-pr-body` reports with). missing: the
#   headings of the profile's `## PR` `Template:` file, read from the checkout
#   root, that the body lacks; [] where there is no profile, the Template: is
#   None. or its file is not there.
# exit: 0 · 2 the PR could not be read
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: read-pr <pr>'
ship_help "$usage" "$@"
ship_args "$usage" pr "$@"
pr=$1
[ $# -eq 1 ] || ship_tooling "unknown flag: $2"
ship_load_host

pull=$(host_pr_get "$pr") || ship_tooling "cannot read PR $pr"
headings=$(ship_body_headings "$(jq -r '.body // ""' <<<"$pull")" | jq -R . | jq -sc .)

wanted='[]'
if profile=$(ship_profile_path) && [ -f "$profile" ]; then
  template=$(awk '/^## /{f = ($0 ~ /^## PR[ \t\r]*$/)} f && /^Template:/{sub(/^Template:[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit}' "$profile")
  file=$(git rev-parse --show-toplevel)/$template
  case $template in ''|None|None.) ;; *) [ ! -f "$file" ] || wanted=$(ship_body_headings "$(cat "$file")" | jq -R . | jq -sc .) ;; esac
fi
jq --argjson h "$headings" --argjson w "$wanted" '. + {headings: $h, missing: ($w - $h)}' <<<"$pull"
