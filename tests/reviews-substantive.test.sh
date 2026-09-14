#!/usr/bin/env bash
# `_gh_reviews_projection` and `SHIP_LANDED_BY`: the chain that decides whether
# a round landed. A review whose body is only a quota notice is not a round, so
# it is `substantive: false` and neither landing rule can land off it (issue
# #155). Pure jq over review objects; no call in this file reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh
SHIP_OWNER=o SHIP_REPO=r
source skills/ship/scripts/host/github.sh

notice='Copilot was unable to review this pull request because the user who requested the review has reached their quota limit.'
bot='copilot-pull-request-reviewer[bot]'

# review <id> <sha> <at> <body>: one raw GitHub review object.
review() {
  jq -n --arg id "$1" --arg sha "$2" --arg at "$3" --arg b "$4" --arg l "$bot" \
    '{id: ($id | tonumber), user: {login: $l}, state: "COMMENTED",
      body: $b, submitted_at: $at, commit_id: $sha}'
}
# project <head-sha> <review>...: the adapter's call, in isolation.
project() { local sha=$1; shift; jq -s --arg sha "$sha" --argjson full '[]' "$_gh_reviews_projection" <<<"$*"; }
# landed <normalised-login> <since> <projection>: poll-pr's landing rules.
landed() { jq -r --arg l "$1" --arg s "$2" "$SHIP_LANDED_BY" <<<"$3"; }

head=abc123
notice_round=$(project $head "$(review 1 $head 2026-09-14T09:00:00Z "$notice")")
real_round=$(project $head "$(review 2 $head 2026-09-14T09:00:00Z 'Reviewed 3 files. One finding in poll-pr.sh.')")
empty_round=$(project $head "$(review 3 $head 2026-09-14T09:00:00Z '')")

check "a notice round is not substantive" \
  false "$(jq -r '.on_head[0].substantive' <<<"$notice_round")"

check "a notice round still carries its body, so the run can see why it waited" \
  "$notice" "$(jq -r '.on_head[0].body' <<<"$notice_round")"

check "a notice round still appears in on_head[] and all[]" \
  "1 1" "$(jq -r '[(.on_head | length), (.all | length)] | join(" ")' <<<"$notice_round")"

check "a real round is unchanged" \
  true "$(jq -r '.on_head[0].substantive' <<<"$real_round")"

check "an empty body is still not a round" \
  false "$(jq -r '.on_head[0].substantive' <<<"$empty_round")"

check "a round that merely mentions a quota among its findings is a round" \
  true "$(jq -r '.on_head[0].substantive' <<<"$(project $head "$(review 4 $head 2026-09-14T09:00:00Z \
    'Reviewed 3 files.
The retry should back off rather than burn the API quota.')")")"

check "the head rule cannot land off a notice round" \
  null "$(landed copilot-pull-request-reviewer '' "$notice_round")"

check "the since rule cannot land off a notice round" \
  null "$(landed copilot-pull-request-reviewer 2026-09-14T08:00:00Z "$notice_round")"

check "the head rule still lands a real round" \
  head "$(landed copilot-pull-request-reviewer '' "$real_round")"

check "the since rule still lands a real round" \
  since "$(landed copilot-pull-request-reviewer 2026-09-14T08:00:00Z "$real_round")"

check "a real round on the same head lands past a notice round" \
  head "$(landed copilot-pull-request-reviewer '' \
    "$(project $head "$(review 1 $head 2026-09-14T09:00:00Z "$notice")" \
                      "$(review 2 $head 2026-09-14T09:30:00Z 'Reviewed 3 files. One finding.')")")"

finish
