#!/usr/bin/env bash
# PR-body check: refuse a PR body that lacks a `##` heading its template has.
#
# Ship writes a body section by rewriting the text under its heading, so a heading
# a body lacks is a section no later phase can fill, and one written by hand
# without the template is how it goes missing. The template is the source of
# truth: a heading added to it is required of every body from then on.
#
#   scripts/check-pr-body.sh [<body-file>]      the body on stdin when no file is given
#
# PR_TEMPLATE overrides the template, default .github/pull_request_template.md.
# Headings are level 2 and matched whole, ignoring trailing whitespace and CRLF;
# a line inside a fenced block or an HTML comment renders as prose, so it is not a
# heading in the body or in the template.
#
# stdout: one `pr-body: missing heading: <heading>` line per missing heading
# exit: 0 the body carries every heading · 1 it does not · 2 tooling
set -uo pipefail

template=${PR_TEMPLATE:-$(dirname "${BASH_SOURCE[0]}")/../.github/pull_request_template.md}
[ -r "$template" ] || { echo "pr-body: cannot read the template $template" >&2; exit 2; }

# Reads a document on stdin, prints its level-2 headings.
headings() {
  awk '
    { sub(/\r$/, "") }
    incomment { if ($0 ~ /-->/) incomment = 0; next }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^<!--/ { if ($0 !~ /-->/) incomment = 1; next }
    /^## / { sub(/[[:space:]]+$/, ""); print }
  '
}

wanted=$(headings < "$template")
[ -n "$wanted" ] || { echo "pr-body: the template $template carries no headings" >&2; exit 2; }

if [ "$#" -ge 1 ]; then
  body=$(cat "$1") || exit 2
else
  body=$(cat)
fi

missing=$(printf '%s\n' "$wanted" | grep -Fxv -f <(headings <<<"$body"))
[ -z "$missing" ] && exit 0
printf '%s\n' "$missing" | sed 's/^/pr-body: missing heading: /'
exit 1
