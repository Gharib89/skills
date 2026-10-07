#!/usr/bin/env bash
# PR-body check: refuse a PR body that lacks a `##` heading its template has, or
# whose `## Change outline` does not hold what a reviewer reads it for.
#
# A section ship writes into a body that lacks its heading is created at the end,
# after `## Attribution`; a body written by hand without the template is how a
# heading goes missing. This refuses the absence up front. Order is the author's:
# nothing here holds `## Attribution` last, so a section appended after it once the
# body is edited passes. The template is the source of truth: a heading added to it is required
# of every body from then on.
#
# The Change outline is held to the Shape bullet of
# docs/contributing/standards/release.md, which is stricter here than ship's
# shipped pr-body.md ("preferably 15" lines, with no gate behind it): a reviewer
# reads it as the diff's shape, and a prose paragraph, an oversized tree or an
# unrooted one defeats that. With the heading present, from it to the next `##`
# heading the outline must hold a `diff` fence or a line starting
# `Shape: none, mechanical (`; the first `diff` fence holds at most 15 lines
# between its fence lines; and each root line in it (non-blank, nothing but the
# diff marker column, when it has one, before its first character) carries a file
# path, a token holding `/` or ending `.<1-5 alphanumerics>`, with an optional
# `:` or `,`. A later carrier fence is not checked. A body without the heading
# gets only the missing-heading line.
#
# Each distinct `Closes #N` (or close/fix/resolve in their forms) outside a
# fence is also echoed on stderr with its issue title, so a reviewer confirms
# the PR closes the issue it means to. That is evidence, not a rule: it reads
# `gh`, says `title unavailable` when `gh` is missing or fails, and never
# changes the exit code or stdout.
#
#   scripts/check-pr-body.sh [<body-file>]      the body on stdin when no file is given
#
# PR_TEMPLATE overrides the template, default .github/pull_request_template.md.
# Headings are level 2 and matched whole, ignoring trailing whitespace (a CRLF
# body's `\r` included); a line inside a fenced block or an HTML comment renders
# as prose, so it is not a heading in the body or in the template. A fence is
# closed by the next line opening with its own marker (three backticks or three
# tildes), so a longer fence holding a shorter one is not tracked, and a heading indented or closed
# with `##` is not matched: ship writes neither.
#
# stdout: one `pr-body: ...` line per violation: a missing heading, or a
#         `change outline:` line for the outline rules
# stderr: the `closes #N: <title>` evidence lines, and tooling errors
# exit: 0 no violation · 1 a violation · 2 tooling
set -uo pipefail

template=${PR_TEMPLATE:-$(dirname "${BASH_SOURCE[0]}")/../.github/pull_request_template.md}
[ -r "$template" ] || { echo "pr-body: cannot read the template $template" >&2; exit 2; }

# Reads a document on stdin, prints its level-2 headings.
headings() {
  awk '
    incomment { if ($0 ~ /-->/) incomment = 0; next }
    /^[[:space:]]*```/ && fence != "~" { fence = (fence == "`") ? "" : "`"; next }
    /^[[:space:]]*~~~/ && fence != "`" { fence = (fence == "~") ? "" : "~"; next }
    fence != "" { next }
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

# Reads a body as its one argument, prints one line per Change outline
# violation. The fence and comment tracking is `headings`'s, so what renders as
# prose is skipped here too; `section` is on from the `## Change outline`
# heading to the next heading.
outline_violations() {
  awk '
    function path(line,   n, t, i, s) {
      n = split(line, t, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        if (index(t[i], "/")) return 1
        if (t[i] !~ /\.[A-Za-z0-9][A-Za-z0-9]?[A-Za-z0-9]?[A-Za-z0-9]?[A-Za-z0-9]?[:,]?$/) continue
        # A stem of digits and dots is a version (24.2.9), not a file name.
        s = t[i]; sub(/[:,]$/, "", s); sub(/\.[A-Za-z0-9]+$/, "", s)
        if (s !~ /^[0-9.]+$/) return 1
      }
      return 0
    }
    function close_fence() {
      if (!isdiff || seen_diff) return
      seen_diff = 1
      if (lines > 15) print "pr-body: change outline: the Shape fence is " lines " lines, over 15"
      for (i = 1; i <= roots; i++) if (!path(root[i])) print "pr-body: change outline: tree root has no file path: " root[i]
    }
    function end_section() {
      if (section && !seen_diff && !shape) print "pr-body: change outline: neither a Shape diff fence nor a \"Shape: none, mechanical (\" line"
      section = 0
    }
    { sub(/\r$/, "") }
    incomment { if ($0 ~ /-->/) incomment = 0; next }
    /^[[:space:]]*```/ && fence != "~" || /^[[:space:]]*~~~/ && fence != "`" {
      marker = ($0 ~ /^[[:space:]]*`/) ? "`" : "~"
      if (fence == "") {
        fence = marker; info = $0
        sub(/^[[:space:]]*(```|~~~)[`~]*[[:space:]]*/, "", info); sub(/[[:space:]]+$/, "", info)
        isdiff = section && info == "diff" && !seen_diff
        lines = 0; roots = 0
      } else {
        fence = ""
        if (isdiff) close_fence()
        isdiff = 0
      }
      next
    }
    fence != "" {
      if (isdiff) {
        lines++
        rest = ($0 ~ /^[-+ ]/) ? substr($0, 2) : $0
        if ($0 !~ /^[[:space:]]*$/ && rest ~ /^[^[:space:]]/) root[++roots] = rest
      }
      next
    }
    /^## / {
      h = $0; sub(/[[:space:]]+$/, "", h)
      end_section()
      if (h == "## Change outline") { section = 1; seen_diff = 0; shape = 0 }
      next
    }
    /<!--/ { if ($0 !~ /-->/) incomment = 1; next }
    section && /^Shape: none, mechanical \(/ { shape = 1 }
    END { if (fence != "" && isdiff) close_fence(); end_section() }
  ' <<<"$1"
}

# Reads a body on stdin, prints each distinct issue number a closing keyword
# names outside a fence, in order.
closed_issues() {
  awk '
    { sub(/\r$/, "") }
    /^[[:space:]]*```/ && fence != "~" { fence = (fence == "`") ? "" : "`"; next }
    /^[[:space:]]*~~~/ && fence != "`" { fence = (fence == "~") ? "" : "~"; next }
    fence != "" { next }
    {
      line = tolower($0)
      while (match(line, /(^|[^a-z0-9])(close[sd]?|fix(e[sd])?|resolve[sd]?) #[0-9]+/)) {
        hit = substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH)
        sub(/.*#/, "", hit)
        if (!(hit in seen)) { seen[hit] = 1; print hit }
      }
    }
  '
}

# Evidence only: a failing or missing gh must not reach the verdict.
while read -r n; do
  [ -n "$n" ] || continue
  title=$(gh issue view "$n" --json title --jq .title </dev/null 2>/dev/null) && [ -n "$title" ] || title="title unavailable"
  echo "pr-body: closes #$n: $title" >&2
done < <(closed_issues <<<"$body")

# grep -v exits 1 when it selects nothing, which is every heading present; 2 is grep
# itself failing, which must not read as a pass.
missing=$(printf '%s\n' "$wanted" | grep -Fxv -f <(headings <<<"$body"))
case $? in
  1) missing= ;;
  0) missing=$(printf '%s\n' "$missing" | sed 's/^/pr-body: missing heading: /') ;;
  *) echo "pr-body: grep failed" >&2; exit 2 ;;
esac
violations=$(outline_violations "$body")

[ -n "$missing$violations" ] || exit 0
printf '%s\n' "$missing${missing:+${violations:+$'\n'}}$violations"
exit 1
