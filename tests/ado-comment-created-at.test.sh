#!/usr/bin/env bash
# host_pr_comment() on Azure DevOps must report the host's own creation time for
# the comment it posted (#164). `request-review`'s comment transport reports that
# value as `requested_at` and phase 7 hands it to `poll-pr --since`, so a wall
# clock read on a machine whose clock drifts widens that window or strands the
# round it asked for.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
# The adapter reads these at source time; `invoke` is stubbed below, so no case
# here reaches a host.
SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/ado.sh

body=$(mktemp); FIXTURE=$(mktemp)
trap 'rm -f "$body" "$FIXTURE"' EXIT
printf 'a comment\n' > "$body"
invoke() { cat "$FIXTURE"; }

# The thread the POST returns is the case's input; the mechanic's own output is
# what every case asserts on. The call runs in a subshell because
# host_pr_comment sets a RETURN trap on a local: called from inside another
# function, that trap fires again when this helper returns, when the local is
# already out of scope and `set -u` reports it. Real callers invoke the
# mechanic from script top level, where it fires once and in scope.
posted() { printf '%s' "$1" > "$FIXTURE"; ( host_pr_comment 7 "$body" ); }

# The spelling the API returns for a comment: fractional seconds and a Z.
check "comment publishedDate, fractional seconds stripped" \
  "2026-09-15T14:22:28Z" \
  "$(posted '{"id": 41, "publishedDate": "2026-09-15T09:00:00.000Z",
              "comments": [{"id": 1, "publishedDate": "2026-09-15T14:22:28.343Z"}]}' | jq -r '.created_at')"

# Already in the target spelling: both subs must no-op rather than eat a digit.
check "no fractional seconds, passed through unchanged" \
  "2026-09-15T14:22:28Z" \
  "$(posted '{"id": 41, "comments": [{"id": 1, "publishedDate": "2026-09-15T14:22:28Z"}]}' | jq -r '.created_at')"

# The other spelling the API mixes in, which `_utc` folds to the first.
check "offset spelling folded to Z" \
  "2026-09-15T14:22:46Z" \
  "$(posted '{"id": 41, "comments": [{"id": 1, "publishedDate": "2026-09-15T14:22:46.977591+00:00"}]}' | jq -r '.created_at')"

# The thread carries a time the comment lacks.
check "falls back to the thread's publishedDate" \
  "2026-09-15T09:00:00Z" \
  "$(posted '{"id": 41, "publishedDate": "2026-09-15T09:00:00.000Z", "comments": [{"id": 1}]}' | jq -r '.created_at')"

# Neither records a time: null, which the contract permits and the transport
# answers with its wall clock read from before the post.
check "null where the response records no time" \
  "null" \
  "$(posted '{"id": 41, "comments": [{"id": 1}]}' | jq -r '.created_at')"

check "null where the response carries no comments at all" \
  "null" \
  "$(posted '{"id": 41}' | jq -r '.created_at')"

# The fields that were already there are untouched.
out=$(posted '{"id": 41, "comments": [{"id": 1, "publishedDate": "2026-09-15T14:22:28.343Z"}]}')
check "id unchanged"  "41" "$(jq -r '.id' <<<"$out")"
check "url unchanged" "https://dev.azure.com/org/proj/_git/repo/pullrequest/7?discussionId=41" "$(jq -r '.url' <<<"$out")"

finish
