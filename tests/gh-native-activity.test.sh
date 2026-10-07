#!/usr/bin/env bash
# `host_pr_native_activity`: the GitHub adapter's read of what native Codex
# review leaves on a PR, and its pick of the request comment whose reactions it
# reads: the latest comment opening with the phrase at or after <since>. The
# function runs with the adapter's `api` redefined to answer per endpoint what
# its own `--jq` would print, so no call in this file reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh
SHIP_OWNER=o SHIP_REPO=r
source skills/ship/scripts/host/github.sh

log=$(mktemp); trap 'rm -f "$log"' EXIT
comment() { # <id> <created_at> <body>
  jq -cn --argjson i "$1" --arg c "$2" --arg b "$3" \
    '{id: $i, login: "me", created_at: $c, updated_at: $c, body: $b, url: "u"}'
}
eyes='{"content":"eyes","login":"chatgpt-codex-connector[bot]","created_at":"2026-10-07T12:28:24Z"}'
COMMENTS='' FAIL=''
api() {
  printf '%s\n' "$1" >> "$log"
  case $1 in
    repos/o/r/issues/7/comments) [ "$FAIL" != comments ] || return 1; printf '%s' "$COMMENTS" ;;
    repos/o/r/issues/7/reactions) [ "$FAIL" != reactions ] || return 1 ;;
    repos/o/r/issues/comments/*/reactions) [ "$FAIL" != request ] || return 1; printf '%s\n' "$eyes" ;;
    *) echo "unexpected api call: $*" >&2; return 1 ;;
  esac
}
read_at() { : > "$log"; host_pr_native_activity 7 "$1" '@codex review'; }

# An earlier request, the one being polled, and a later comment quoting the
# phrase mid-sentence: the pick is the latest one OPENING with it.
COMMENTS=$(printf '%s\n%s\n%s\n' \
  "$(comment 10 2026-10-07T12:12:24Z '@codex review')" \
  "$(comment 11 2026-10-07T12:28:13Z $'@codex review\n<span data-ship=1></span>')" \
  "$(comment 12 2026-10-07T12:29:00Z 'asked @codex review above')")
out=$(read_at 2026-10-07T12:28:13Z)
check "the request comment is the latest opening with the phrase since the request" \
  "repos/o/r/issues/comments/11/reactions" "$(grep comments/ "$log")"
check "its reactions are the request's" '[{"content":"eyes","login":"chatgpt-codex-connector[bot]","created_at":"2026-10-07T12:28:24Z"}]' \
  "$(jq -c .request_reactions <<<"$out")"
check "every comment comes back" 3 "$(jq '.comments | length' <<<"$out")"
check "the PR's reactions read empty as []" '[]' "$(jq -c .pr_reactions <<<"$out")"

# No request at or after <since>: no reaction read, an empty list.
out=$(read_at 2026-10-07T13:00:00Z)
check "no request since <since> reads no request reactions" '[] 0' \
  "$(jq -c .request_reactions <<<"$out") $(grep -c comments/ "$log")"

# Any read failing fails the whole read, which poll-pr reports unavailable.
for f in comments reactions request; do
  FAIL=$f
  read_at 2026-10-07T12:28:13Z >/dev/null 2>&1
  check_rc "a failed $f read fails the activity read" 1 "$?"
done

finish
