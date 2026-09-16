#!/usr/bin/env bash
# update-pr-body's guards: the usage line, an unknown flag, the two body-address
# flags, and the body file whose fence state ends open. Every case here is
# malformed, so the guard answers before `ship_load_host` and nothing reaches a
# host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

m=skills/ship/scripts/update-pr-body.sh
usage='usage: update-pr-body <pr> (--section <name> | --preamble) --body-file <path>'

err() { bash "$m" "$@" 2>/dev/null | jq -r '.error'; }
rc()  { bash "$m" "$@" >/dev/null 2>&1; echo $?; }

check "a bare invocation prints the usage line" "$usage" "$(err)"
check "an unknown flag is named" 'unknown flag: --body' "$(err 7 --body x)"

# The PR number forgotten in front of the flags: without the guard "--section"
# is the PR number and the host is asked for it.
check "a flag in the PR slot is the usage error" "$usage" "$(err --section Review --body-file /dev/null)"
check_rc "a flag in the PR slot is tooling" 2 "$(rc --section Review --body-file /dev/null)"

# The two ways to address the body are exclusive: a call carrying both asks for
# two different rewrites of the same body, and a call carrying neither says
# nothing about which part of it to replace.
check "both address flags is the usage error" "$usage" \
  "$(err 7 --section Review --preamble --body-file /dev/null)"
check_rc "both address flags is tooling" 2 "$(rc 7 --section Review --preamble --body-file /dev/null)"
check "neither address flag is the usage error" "$usage" "$(err 7 --body-file /dev/null)"
check_rc "neither address flag is tooling" 2 "$(rc 7 --body-file /dev/null)"

# A flag where a flag's value belongs: without the guard `--preamble` is the
# section name, so the call is accepted and the exclusion it breaks never fires.
check "a flag in the section slot is the usage error" "$usage" \
  "$(err 7 --section --preamble --body-file /dev/null)"
check_rc "a flag in the section slot is tooling" 2 "$(rc 7 --section --preamble --body-file /dev/null)"
check "a flag in the body-file slot is the usage error" "$usage" \
  "$(err 7 --section Review --body-file --preamble)"

open_fence=$(mktemp); heading=$(mktemp)
trap 'rm -f "$open_fence" "$heading"' EXIT
printf 'a lede\n\n## Summary\n' > "$heading"

# The preamble is what sits above the first heading, so a heading in the file
# opens a section, and the carried closing line then lands inside it.
check "a preamble file carrying a heading is refused" \
  'a preamble carries no `## ` heading: the preamble ends at the first one' \
  "$(err 7 --preamble --body-file "$heading")"
check_rc "a heading in a preamble file is tooling" 2 "$(rc 7 --preamble --body-file "$heading")"

# A heading with no text is the one most likely to be a typo, and it is also the
# one whose heading TEXT is empty, so the refusal counts the headings rather
# than reading them.
printf 'a lede\n\n## \n' > "$heading"
check "a preamble file carrying an empty heading is refused too" \
  'a preamble carries no `## ` heading: the preamble ends at the first one' \
  "$(err 7 --preamble --body-file "$heading")"

printf '## Summary\n\n```diff\n- before\n+ after\n' > "$open_fence"

# Run #121: two Summary rewrites on an unclosed Shape fence swallowed four
# sections, and the verdict still said `replaced: true`. The refusal names the
# fence so the caller can close it rather than hunt for it.
check "a body file whose fence ends open is refused, naming the fence" \
  'body file ends inside an unclosed fence (line 3: ```)' \
  "$(err 7 --section Summary --body-file "$open_fence")"
check_rc "an unclosed fence is tooling, not a failed update" \
  2 "$(rc 7 --section Summary --body-file "$open_fence")"

# The preamble file takes the same rule: an open fence there inverts the state
# for the whole body under it, which is the same swallowed sections.
check "a preamble file whose fence ends open is refused too" \
  'body file ends inside an unclosed fence (line 3: ```)' \
  "$(err 7 --preamble --body-file "$open_fence")"
check_rc "an unclosed preamble fence is tooling" 2 "$(rc 7 --preamble --body-file "$open_fence")"

finish
