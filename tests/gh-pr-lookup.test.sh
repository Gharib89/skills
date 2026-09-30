#!/usr/bin/env bash
# The GitHub adapter's two open-PR lookups, host_pr_create's re-read and
# host_pr_for_branch, must send the branch to `gh api` as an encoded field on an
# explicit GET. Git refnames accept `&`, `#` and `+`, so a slug spliced into the
# query string corrupts the `head=` filter, and the lookup then misses a PR that
# was just opened (a flaky create would open a duplicate). `-f` makes `gh`
# encode the value; without an explicit method `gh api` sends a POST once a
# field is present, which the adapter's retry would then treat as a read. A fake
# `gh` on PATH records each call's argv, one word per line, so the request is
# what every case asserts on and nothing reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
# The adapter reads these at source time; no call in this file reaches a host.
SHIP_OWNER=owner SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh
sleep() { :; }

bin=$(mktemp -d) || exit 2
trap 'rm -rf "$bin"' EXIT
export GH_ARGV_LOG=$bin/argv
cat > "$bin/gh" <<'FAKE'
#!/usr/bin/env bash
{ printf '%s\n' "--"; printf '%s\n' "$@"; } >> "$GH_ARGV_LOG"
case " $* " in
  *" POST "*) cat > /dev/null; echo "gh: HTTP 500" >&2; exit 1 ;;
esac
printf 'HTTP/2.0 200 OK\r\n\r\n{"number":5,"url":"u","created_at":"t","state":"open","head_sha":"s"}\n'
FAKE
chmod +x "$bin/gh"
PATH=$bin:$PATH

slug='feat/a&b#c+d'
body=$bin/body; printf 'b' > "$body"

# The last call's words, one per line, after the final `--` marker.
last_call() { awk '/^--$/ { n = ""; next } { n = n $0 "\n" } END { printf "%s", n }' "$GH_ARGV_LOG"; }
has_pair() { printf '%s' "$1" | grep -A1 -Fx -- "$2" | grep -Fxq -- "$3" && echo yes || echo no; }

: > "$GH_ARGV_LOG"
host_pr_create "$slug" main title "$body" "" >/dev/null 2>&1
call=$(last_call)
check "create re-read: an explicit GET" yes "$(has_pair "$call" -X GET)"
check "create re-read: state is a field" yes "$(has_pair "$call" -f state=open)"
check "create re-read: head is a field, unescaped" yes "$(has_pair "$call" -f "head=owner:$slug")"
check "create re-read: no query string on the route" "" "$(printf '%s' "$call" | grep -F '?')"

: > "$GH_ARGV_LOG"
host_pr_for_branch "$slug" >/dev/null 2>&1
call=$(last_call)
check "branch lookup: an explicit GET" yes "$(has_pair "$call" -X GET)"
check "branch lookup: state is a field" yes "$(has_pair "$call" -f state=all)"
check "branch lookup: head is a field, unescaped" yes "$(has_pair "$call" -f "head=owner:$slug")"
check "branch lookup: no query string on the route" "" "$(printf '%s' "$call" | grep -F '?')"

finish
