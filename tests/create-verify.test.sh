#!/usr/bin/env bash
# _gh_create_verify: the GitHub adapter's create-then-verify sequence. The post
# and find functions here are stubs, so no case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
# The adapter reads these at source time; no call in this file reaches a host.
SHIP_OWNER=owner SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh

# The helper runs each stub in a command substitution, so the call trace lives
# in a file rather than a variable a subshell would drop. Asserting the order,
# not just the count, is what holds the helper to create-then-verify: a helper
# that retried the post without the re-read would post twice either way.
calls=$(mktemp); trap 'rm -f "$calls"' EXIT
trace() { paste -sd, "$calls"; }
reset() { : > "$calls"; }
mark()  { echo "$1" >> "$calls"; }

# A create that works: one POST, its row, and no re-read.
_post() { mark post; echo '{"number":1}'; }
_find() { mark find; echo '{"number":9}'; }
reset
check    "prints the row a successful post returned" '{"number":1}' "$(_gh_create_verify _post _find)"
check    "posts once and never re-reads when the post succeeds" post "$(trace)"

# A slow success: the post reports failure but the row is there, so the row is
# returned and the create is not attempted again.
_post() { mark post; return 1; }
_find() { mark find; echo '{"number":2}'; }
reset
out=$(_gh_create_verify _post _find); rc=$?
check    "returns the row a slow success left"              '{"number":2}' "$out"
check_rc "reports success for a row found by the re-read"   0 "$rc"
check    "re-reads once and does not post again"                post,find "$(trace)"

# A genuine failure: the re-read succeeds and shows no row, so the create is
# attempted once more.
_post() { mark post; [ "$(grep -c post "$calls")" -lt 2 ] && return 1; echo '{"number":3}'; }
_find() { mark find; }
reset
out=$(_gh_create_verify _post _find); rc=$?
check    "retries the post when the re-read finds nothing" '{"number":3}' "$out"
check_rc "reports success for the retried post"            0 "$rc"
check    "re-reads between the two posts"                  post,find,post "$(trace)"

# A failed re-read is not an absent row: it answers unknown, so the caller gets
# the failure rather than a second POST that would double-post a slow success.
_post() { mark post; return 1; }
_find() { mark find; return 1; }
reset
out=$(_gh_create_verify _post _find); rc=$?
check    "prints nothing when the re-read fails"      "" "$out"
check_rc "reports failure when the re-read fails"     1 "$rc"
check    "stops at the failed re-read"                post,find "$(trace)"

finish
