#!/usr/bin/env bash
# `_gh_blocked_select`: the GitHub adapter's selection over the awaited login's
# PR comments AND review bodies, which is what `host_pr_reviewer_blocked`
# returns. A pure jq transformation over rows; no call in this file reaches a
# host. The notice text is PR #154's, where Copilot answered three rounds with
# it and `reviewer_blocked` stayed null (issue #155).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh
SHIP_OWNER=o SHIP_REPO=r
source skills/ship/scripts/host/github.sh

notice='Copilot was unable to review this pull request because the user who requested the review has reached their quota limit.'

# select <login> <rows-json>: the adapter's call, in isolation.
select_blocked() { jq -r --arg l "$1" "$_gh_blocked_select" <<<"$2"; }

row() { # <login> <at> <body>
  jq -n --arg l "$1" --arg at "$2" --arg b "$3" '{login: $l, at: $at, body: $b}'
}
rows() { jq -s . <<<"$*"; }

bot='copilot-pull-request-reviewer[bot]'

check "a notice in a review body, with no comment carrying one" \
  "$notice" \
  "$(select_blocked "$bot" "$(rows "$(row "$bot" 2026-09-14T09:00:00Z "$notice")")")"

check "no row carries the vocabulary" \
  null \
  "$(select_blocked "$bot" "$(rows "$(row "$bot" 2026-09-14T09:00:00Z 'Reviewed 3 files and found no issues.')")")"

check "another login's notice is not this reviewer's" \
  null \
  "$(select_blocked "$bot" "$(rows "$(row someone-else 2026-09-14T09:00:00Z "$notice")")")"

check "the most recent notice wins across the two surfaces" \
  'later quota notice' \
  "$(select_blocked "$bot" "$(rows \
      "$(row "$bot" 2026-09-14T09:00:00Z 'earlier rate limit notice')" \
      "$(row "$bot" 2026-09-14T10:00:00Z 'later quota notice')")")"

check "rows out of chronological order still answer with the latest" \
  'later quota notice' \
  "$(select_blocked "$bot" "$(rows \
      "$(row "$bot" 2026-09-14T10:00:00Z 'later quota notice')" \
      "$(row "$bot" 2026-09-14T09:00:00Z 'earlier rate limit notice')")")"

check "a quoted, bolded notice line is returned bare" \
  'Next included review is in 3 days' \
  "$(select_blocked "$bot" "$(rows "$(row "$bot" 2026-09-14T09:00:00Z '> **Next included review is in 3 days**')")")"

check "a null body is not a notice" \
  null \
  "$(select_blocked "$bot" '[{"login":"copilot-pull-request-reviewer[bot]","at":"2026-09-14T09:00:00Z","body":null}]')"

finish
