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

# The helper runs each stub in a command substitution, so the post count lives
# in a file rather than a variable a subshell would drop.
posts=$(mktemp); trap 'rm -f "$posts"' EXIT
count() { wc -l < "$posts" | tr -d ' '; }
reset() { : > "$posts"; }
mark()  { echo x >> "$posts"; }

# A create that works: one POST, its row, and no re-read.
_post() { mark; echo '{"number":1}'; }
_find() { echo '{"number":9}'; }
reset
check    "prints the row a successful post returned" '{"number":1}' "$(_gh_create_verify _post _find)"
check_rc "posts exactly once when the post succeeds" 1 "$(count)"

# A slow success: the post reports failure but the row is there, so the row is
# returned and the create is not attempted again.
_post() { mark; return 1; }
_find() { echo '{"number":2}'; }
reset
out=$(_gh_create_verify _post _find); rc=$?
check    "returns the row a slow success left"              '{"number":2}' "$out"
check_rc "reports success for a row found by the re-read"   0 "$rc"
check_rc "does not post again when the re-read finds a row" 1 "$(count)"

# A genuine failure: the re-read succeeds and shows no row, so the create is
# attempted once more.
_post() { mark; [ "$(count)" -lt 2 ] && return 1; echo '{"number":3}'; }
_find() { :; }
reset
out=$(_gh_create_verify _post _find); rc=$?
check    "retries the post when the re-read finds nothing" '{"number":3}' "$out"
check_rc "reports success for the retried post"            0 "$rc"
check_rc "posts exactly twice for a genuine failure"       2 "$(count)"

# A failed re-read is not an absent row: it answers unknown, so the caller gets
# the failure rather than a second POST that would double-post a slow success.
_post() { mark; return 1; }
_find() { return 1; }
reset
out=$(_gh_create_verify _post _find); rc=$?
check    "prints nothing when the re-read fails"      "" "$out"
check_rc "reports failure when the re-read fails"     1 "$rc"
check_rc "does not post again when the re-read fails" 1 "$(count)"

finish
