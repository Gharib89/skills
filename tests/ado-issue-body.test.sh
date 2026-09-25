#!/usr/bin/env bash
# An Azure DevOps description as `update-issue-body` meets it (#289):
# host_issue_body unwraps the one `<pre>` block ship writes, the section surgery
# runs on the markdown, and host_issue_set_body wraps it again. The fixture is
# the shape the lab returned for a `_html_pre` write: its sanitizer hands `"`
# back as `&quot;` and U+00A0 as `&nbsp;`, besides the three `_html_pre`
# escapes. `azx` is stubbed, so no case here reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/ado.sh

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
azx() { # work-item show answers the fixture; update records its --description
  case "$1 $2 $3" in
    "boards work-item show") jq -n --rawfile d "$work/desc" '{id: 7, fields: {"System.Description": $d}}' ;;
    "boards work-item update") while [ $# -gt 0 ]; do [ "$1" = --description ] && printf '%s' "$2" > "$work/written"; shift; done ;;
  esac
}
desc() { printf '%s' "$1" > "$work/desc"; }

nb=$'\xc2\xa0'
desc $'<pre>## A\n\na &amp;amp; b &lt;x&gt; &quot;q&quot; \'s\' nb&nbsp;x\n\n## B\n\nold\n</pre>'
md=$'## A\n\na &amp; b <x> "q" \'s\' nb'"$nb"$'x\n\n## B\n\nold\n'
out=$(host_issue_body 7); rc=$?
check_rc "a single <pre> description reads" 0 "$rc"
check "unwrapped to the markdown ship wrote, entities decoded once" "${md}." "$(jq -j .body <<<"$out"; printf .)"

printf 'new\n' > "$work/section.md"
# As update-issue-body writes it: the surgery, ending in exactly one newline.
printf '%s\n' "$(ship_body_replace_section "$(jq -r .body <<<"$out")" B "$work/section.md")" > "$work/new.md"
host_issue_set_body 7 "$work/new.md"
check "re-wrapped as one <pre> block, the untouched section intact" \
  $'<pre>## A\n\na &amp;amp; b &lt;x&gt; "q" \'s\' nb'"$nb"$'x\n\n## B\n\nnew\n</pre>' "$(cat "$work/written")"

desc ''
check "an empty description is an empty body" '{"body":""}' "$(host_issue_body 7 | jq -c .)"

desc '<div>a human wrote this</div>'
out=$(host_issue_body 7); rc=$?
check_rc "any other description shape is refused" 1 "$rc"
check "with a reason saying so" true "$(jq -r '.reason | test("pre")' <<<"$out")"

# Two blocks, or HTML after the block, is not the shape ship writes.
desc '<pre>a</pre><p>b</p>'
check_rc "a <pre> block with HTML beside it is refused too" 1 "$(host_issue_body 7 >/dev/null; echo $?)"

# Oniguruma's `$` matches before a final newline too: anchored with it, this
# passed the test and the fixed slice cut `x</pre>` to `x<`.
desc $'<pre>x</pre>\n'
check_rc "a <pre> block followed by a newline is refused, not mis-sliced" 1 "$(host_issue_body 7 >/dev/null; echo $?)"

finish
