#!/usr/bin/env bash
# Shared reading for the bump-guard job's PR checks (check-grade-statement.sh,
# check-fix-scope.sh): the environment seam, and a body line found outside HTML
# comments. Sourced, never run.
#
#   pr_check_init <check-name>        sets title, body, base and root from
#                                     PR_TITLE, PR_BODY, PR_BASE and PR_ROOT
#                                     (default: the checkout holding the check);
#                                     exits 2 on an unset or unknown PR_BASE
#   pr_body_has_line <heading> <ere>  prints yes or no: a body line matching the
#                                     ERE, within the `## <heading>`
#                                     section, or anywhere when <heading> is empty

# shellcheck disable=SC2034  # the variables are read by the sourcing check
pr_check_init() {
  title=${PR_TITLE:-}
  body=${PR_BODY:-}
  base=${PR_BASE:-}
  root=${PR_ROOT:-$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)}
  [ -n "$base" ] || { echo "$1: PR_BASE is not set" >&2; exit 2; }
  git -C "$root" rev-parse --verify -q "$base^{commit}" >/dev/null || { printf '%s: no such ref: %s\n' "$1" "$base" >&2; exit 2; }
}

# An HTML comment renders as nothing, so a line inside one does not count.
pr_body_has_line() {
  printf '%s\n' "$body" | awk -v heading="$1" -v re="$2" '
    /^## / { on = (heading == "" || $0 ~ ("^## " heading "[ \t]*\r?$")); next }
    heading != "" && !on { next }
    { line = $0
      while (1) {
        if (cm) { i = index(line, "-->"); if (!i) { line = ""; break } line = substr(line, i + 3); cm = 0 }
        i = index(line, "<!--"); if (!i) break
        j = index(substr(line, i + 4), "-->")
        if (j) line = substr(line, 1, i - 1) substr(line, i + 4 + j + 2)
        else { line = substr(line, 1, i - 1); cm = 1; break }
      }
      if (line ~ re) found = 1 }
    END { print found ? "yes" : "no" }'
}
