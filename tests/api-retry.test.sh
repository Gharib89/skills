#!/usr/bin/env bash
# api(): the GitHub adapter's REST wrapper. Its one retry must resend the
# request the first attempt sent, the stdin payload included (#108). A fake
# `gh` on PATH records what each attempt received, so no case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
# The adapter reads these at source time; no call in this file reaches a host.
SHIP_OWNER=owner SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh

# The wrapper waits between attempts. The retry policy is not under test, the
# bytes the retry sends are, so a no-op shadows the 2 s sleep.
sleep() { :; }

bin=$(mktemp -d); trap 'rm -rf "$bin"' EXIT
PATH=$bin:$PATH
export GH_LOG=$bin/calls

# The fake resolves `--input` the way `gh` does, `-` from stdin and anything
# else from that file, then logs the attempt number and the body it received.
# A failing attempt drains stdin before it exits, which is what empties the
# pipe for the retry and is the whole bug.
cat > "$bin/gh" <<'FAKE'
#!/usr/bin/env bash
input="" prev=""
for a in "$@"; do
  case $a in --input=*) input=${a#--input=} ;; *) [ "$prev" = --input ] && input=$a ;; esac
  prev=$a
done
case $input in
  "") body="" ;;
  -)  body=$(cat) ;;
  *)  body=$(cat "$input") ;;
esac
n=$(( $(cat "$GH_LOG.n" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" > "$GH_LOG.n"
printf '%s\t%s\n' "$n" "$body" >> "$GH_LOG"
[ "$n" -le "${GH_FAIL_UNTIL:-0}" ] && exit 1
exit 0
FAKE
chmod +x "$bin/gh"

reset() { : > "$GH_LOG"; printf '0' > "$GH_LOG.n"; }
attempts() { cat "$GH_LOG.n"; }
body_of() { awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$GH_LOG"; }

payload='{"body":"a line\nand another"}'

# The bug: the first attempt drains the pipe, so a retry that re-runs the same
# argument list sends nothing and GitHub answers "Body should be a JSON object".
reset; export GH_FAIL_UNTIL=1
printf '%s' "$payload" | api -X PATCH "$R/pulls/1" --input - >/dev/null; rc=$?
check_rc "reports success once the retry lands"        0 "$rc"
check    "retries a failed stdin-fed call once"        2 "$(attempts)"
check    "sends the payload on the first attempt"      "$payload" "$(body_of 1)"
check    "resends the same payload on the retry"       "$payload" "$(body_of 2)"

# A call with no stdin payload keeps its current behaviour: it is retried, and
# nothing tries to read a pipe that was never there.
reset; export GH_FAIL_UNTIL=1
api user --jq .login >/dev/null; rc=$?
check_rc "reports success for a retried read"          0 "$rc"
check    "retries a read once"                         2 "$(attempts)"

# `gh` takes the flag glued to its value too, so the guard reads both spellings
# and a `--input=-` call is buffered like any other.
reset; export GH_FAIL_UNTIL=1
printf '%s' "$payload" | api -X PATCH "$R/pulls/1" --input=- >/dev/null; rc=$?
check_rc "reports success for a glued-flag retry"      0 "$rc"
check    "resends the payload of a glued-flag call"      "$payload" "$(body_of 2)"

# A first attempt that succeeds is the only attempt: the buffering must not
# turn one request into two.
reset; export GH_FAIL_UNTIL=0
printf '%s' "$payload" | api -X PATCH "$R/pulls/1" --input - >/dev/null; rc=$?
check_rc "reports success for a first-attempt success" 0 "$rc"
check    "does not resend a request that succeeded"    1 "$(attempts)"
check    "sends the payload once"                      "$payload" "$(body_of 1)"

finish
