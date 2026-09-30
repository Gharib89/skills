#!/usr/bin/env bash
# PR-body check: refuse a PR body that lacks a `##` heading its template has.
#
# A section ship writes into a body that lacks its heading is created at the end,
# after `## Attribution`, out of template order; a body written by hand without
# the template is how a heading goes missing. The template is the source of truth:
# a heading added to it is required of every body from then on.
#
#   scripts/check-pr-body.sh [<body-file>]      the body on stdin when no file is given
#
# PR_TEMPLATE overrides the template, default .github/pull_request_template.md.
# Headings are level 2 and matched whole, ignoring trailing whitespace (a CRLF
# body's `\r` included); a line inside a fenced block or an HTML comment renders
# as prose, so it is not a heading in the body or in the template. A fence is
# closed by the next line opening with three backticks or tildes, so a longer
# fence holding a shorter one is not tracked, and a heading indented or closed
# with `##` is not matched: ship writes neither.
#
# stdout: one `pr-body: missing heading: <heading>` line per missing heading
# exit: 0 the body carries every heading · 1 it does not · 2 tooling
set -uo pipefail

template=${PR_TEMPLATE:-$(dirname "${BASH_SOURCE[0]}")/../.github/pull_request_template.md}
[ -r "$template" ] || { echo "pr-body: cannot read the template $template" >&2; exit 2; }

# Reads a document on stdin, prints its level-2 headings.
headings() {
  awk '
    incomment { if ($0 ~ /-->/) incomment = 0; next }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^## / { sub(/[[:space:]]+$/, ""); print; next }
    /<!--/ { if ($0 !~ /-->/) incomment = 1 }
  '
}

wanted=$(headings < "$template")
[ -n "$wanted" ] || { echo "pr-body: the template $template carries no headings" >&2; exit 2; }

if [ "$#" -ge 1 ]; then
  body=$(cat "$1") || exit 2
else
  body=$(cat)
fi

# grep -v exits 1 when it selects nothing, which is every heading present; 2 is grep
# itself failing, which must not read as a pass.
missing=$(printf '%s\n' "$wanted" | grep -Fxv -f <(headings <<<"$body"))
case $? in
  1) exit 0 ;;
  0) ;;
  *) echo "pr-body: grep failed" >&2; exit 2 ;;
esac
printf '%s\n' "$missing" | sed 's/^/pr-body: missing heading: /'
exit 1
