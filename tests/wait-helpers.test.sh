#!/usr/bin/env bash
# ship_profile_legs, the wait cursor and ship_poll_read: the helpers `ci-wait`
# and `poll-pr` share. Pure functions sourced and asserted on strings, and
# ship_poll_read over stub reads; no call in this file reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source skills/ship/scripts/_lib.sh

legs() { ship_profile_legs "$1" | paste -sd, -; }
ci=$'## CI\n\n'
check "one inline leg, a semicolon in its description" bump-guard \
  "$(legs "${ci}Legs: bump-guard: the title is a commit; the body carries the template"$'\nNo-checks legal: no')"
check "repeated Legs: lines" test,plugin \
  "$(legs "${ci}Legs: test: npm test"$'\nLegs: plugin: validate\nPush policy: Default.')"
check "a bare Legs: with one leg per line, ended by the next label" lint,test \
  "$(legs "${ci}Legs:"$'\nlint: ruff check\ntest: pytest\nNo-checks legal: yes')"
check "a blank line ends the list" lint \
  "$(legs "${ci}Legs:"$'\nlint: ruff check\n\nprose: not a leg')"
check "Legs: None. names no leg" '' "$(legs "${ci}Legs: None."$'\nNo-checks legal: yes')"
check "a bare Legs: with indented entries, the indent not part of the name" test,lint \
  "$(legs "${ci}Legs:"$'\n  test: npm test\n\tlint: ruff\nPush policy: Default.')"
ship_profile_legs "${ci}Legs: None." >/dev/null; check_rc "None. is an answer" 0 $?
ship_profile_legs "${ci}Push policy: Default." >/dev/null; check_rc "no Legs: line is unknown" 1 $?
check "a Legs: line under another heading is prose" '' \
  "$(legs $'## Verification\n\nLegs: stray: prose\n\n## CI\n\nLegs: None.')"

c=$(ship_cursor_make '{"deadline":12,"since":"2026-01-01T00:00:00Z"}')
check "a cursor reads back the state it was made from" '{"deadline":12,"since":"2026-01-01T00:00:00Z"}' \
  "$(ship_cursor_read "$c")"
refused() { ship_cursor_read "$1" >/dev/null && echo read || echo refused; }
check "a cursor that is not one is refused" refused "$(refused garbage)"
check "a cursor holding no object is refused" refused "$(refused "$(printf '[1]' | base64)")"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
SHIP_HTTP_STATUS_FILE=$tmp/status
answers()  { echo '{"ok":true}'; }
refuses()  { printf 404 > "$SHIP_HTTP_STATUS_FILE"; return 1; }
drops()    { return 1; }
ship_poll_read "$tmp/out" answers; check_rc "an answered read" 0 $?
check "the answer lands in the out file" '{"ok":true}' "$(cat "$tmp/out")"
ship_poll_read "$tmp/out" refuses; check_rc "a read the host refused with a status" 1 $?
ship_poll_read "$tmp/out" drops; check_rc "a read with no HTTP status is no answer yet" 3 $?
refuses >/dev/null; ship_poll_read "$tmp/out" drops; check_rc "the last call's status does not leak into the next" 3 $?

finish
