#!/usr/bin/env bash
# update-pr-body's guards: the usage line, an unknown flag, and the body file
# whose fence state ends open. Every case here is malformed, so the guard answers
# before `ship_load_host` and nothing reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/update-pr-body.sh
usage='usage: update-pr-body <pr> --section <name> --body-file <path>'

err() { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()  { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

check "a bare invocation prints the usage line" "$usage" "$(err)"
check "an unknown flag is named" 'unknown flag: --body' "$(err 7 --body x)"

open_fence=$(mktemp); trap 'rm -f "$open_fence"' EXIT
printf '## Summary\n\n```diff\n- before\n+ after\n' > "$open_fence"

# Run #121: two Summary rewrites on an unclosed Shape fence swallowed four
# sections, and the verdict still said `replaced: true`. The refusal names the
# fence so the caller can close it rather than hunt for it.
check "a body file whose fence ends open is refused, naming the fence" \
  'body file ends inside an unclosed fence (line 3: ```)' \
  "$(err 7 --section Summary --body-file "$open_fence")"
check_rc "an unclosed fence is tooling, not a failed update" \
  2 "$(rc 7 --section Summary --body-file "$open_fence")"

finish
