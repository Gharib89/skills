#!/usr/bin/env bash
# The two read rules of docs/contributing/standards/shell.md, linted. Both
# recurred in merged PRs because nothing looked: a failed read taken as an
# answer (#1088, #1089, #1092, #1135, #1160, #1171) and a list read that stops
# at its first page (#1108, #1161). `scripts/check.sh full` runs each mode as
# its own row, and the edit rung runs both on an edited script through the
# `read-lint` pre-commit hook.
#
#   scripts/read-lint.sh verdict [<script>...]   a failed read taken as a verdict
#   scripts/read-lint.sh paging  [<script>...]   an unpaged list read
#   default files: every *.sh under skills/*/scripts
#
# verdict. A statement is one line, or the lines a trailing backslash joins.
#  - A capture `v=$(gh|api|t3|ffmpeg|nvidia-smi ...)` fails with no `|| exit`
#    (or return, continue, fail, tooling), not under `if`/`!`/`while`, and no
#    `$?`, `[ -n "$v" ]` or `! jq -e` read of it after. `api` is ship's wrapper
#    over `gh api`. `|| v=''` is a deliberate answer, no bare capture, but a
#    later bare `jq -e` over `v` still fails. `jq` is not in that list: a `jq -r` over data the script already holds is not a
#    read of the outside (255 such sites); the `jq -e` form below covers it.
#  - A bare `if jq -e ... <<<"$v"` (not negated) fails when `v` was last
#    captured by `$(...)` with none of those checks and no earlier
#    `! jq -e ... <<<"$v"` validating it: jq's exit 2 or 5 on an empty or
#    broken capture takes the same branch as "no", a silent verdict.
#  Exempt: a statement carrying `# read-checked: <reason>` (the reason is
#  required), on one of its lines or the comment line directly above it, for a
#  read whose failure is the answer on purpose.
#
# paging. A statement with `per_page=` fails unless it carries `--paginate`, or
# the next 8 lines test a full page (`length < 100`, `length == 100`), or it
# carries `# paged: <reason>` (the reason is required), for a read that needs
# only the newest items and so sorts and bounds its page, or follows its own
# paging. The marker sits on a line of the statement or on the comment line
# directly above it, since a trailing backslash leaves no room for one.
#
# stdout: one `<file>:<line>: ...` line per violation, nothing when clean
# exit: 0 clean · 1 a violation · 2 tooling
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

mode=${1:-}
case $mode in verdict | paging) shift ;; *) printf 'usage: read-lint.sh verdict|paging [<script>...]\n' >&2; exit 2 ;; esac
if [ "$#" -eq 0 ]; then
  while IFS= read -r f; do set -- "$@" "$f"; done < <(find skills -path 'skills/*/scripts/*' -name '*.sh' | LC_ALL=C sort)
fi
for f in "$@"; do [ -f "$f" ] || { printf 'not a file: %s\n' "$f" >&2; exit 2; }; done

rc=0
for f in "$@"; do
  out=$(awk -v mode="$mode" '
    # Statements first: a trailing backslash joins the next line.
    { raw[NR] = $0 }
    END {
      n = 0; cur = ""; start = 0
      for (i = 1; i <= NR; i++) {
        l = raw[i]
        if (l ~ /^[ \t]*#/ && cur == "") { lastc = i; lastcl = l; continue }
        if (cur == "") { start = i; above = (lastc == i - 1) ? lastcl : "" }
        joined = (l ~ /\\[ \t]*$/)
        sub(/\\[ \t]*$/, "", l)
        cur = cur " " l
        # An assignment capture runs on while its `$(` is open, so its `|| ...` is read.
        if (!joined && cur ~ /=\$\(/) {
          o = cur; gsub(/[^(]/, "", o); c = cur; gsub(/[^)]/, "", c)
          if (length(o) > length(c) && i < NR) joined = 1
        }
        if (!joined) { n++; st[n] = cur; ab[n] = above; ln[n] = start; endl[n] = i; cur = "" }
      }
      for (s = 1; s <= n; s++) {
        t = st[s]
        mt = t " " ab[s]
        marked = (mt ~ /#[ \t]*read-checked:[ \t]*[^ \t]/)
        if (mode == "paging") {
          if (t !~ /per_page=/ || t ~ /--paginate/ || mt ~ /#[ \t]*paged:[ \t]*[^ \t]/) continue
          ok = 0
          pp = t; sub(/^.*per_page=/, "", pp); sub(/[^0-9].*$/, "", pp)
          rx = "length\\)?[ \t]*(==|<|>=)[ \t]*" pp "([^0-9]|$)"
          if (pp != "" && t ~ rx) ok = 1
          for (i = endl[s] + 1; i <= endl[s] + 8 && i <= NR; i++)
            if (pp != "" && raw[i] ~ rx) ok = 1
          if (!ok) printf "%s:%d: list read with per_page= and no --paginate or full-page refusal; page it, refuse a full page, or mark a newest-items read with a `# paged: <reason>` marker\n", FILENAME, ln[s]
          continue
        }
        code = t; sub(/[ \t]#.*$/, "", code)
        # What each variable was last set from: "capture" (unchecked), "checked" or "other".
        if (match(code, /(^|[ \t;&|(])((local|declare|export)[ \t]+(-[A-Za-z]+[ \t]+)?)?[A-Za-z_][A-Za-z0-9_]*=/)) {
          a = substr(code, RSTART, RLENGTH); sub(/^[ \t;&|(]+/, "", a); sub(/^(local|declare|export)[ \t]+(-[A-Za-z]+[ \t]+)?/, "", a); sub(/=$/, "", a)
          rest = substr(code, RSTART + RLENGTH)
          if (rest ~ /^"?\$\(/) {
            fallback = (code ~ /\|\|/ && code !~ /\|\|[ \t]*(exit|return|continue|break|fail|tooling|die|refuse|unavailable)([ \t;]|$)/)
            checked = ((code ~ /\|\|/ && !fallback) || code ~ /^[ \t]*(if|elif|while|until|!)[ \t]/ || code ~ /\$\?/)
            if (!checked && s < n && (st[s + 1] ~ /^[ \t]*(if[ \t]+)?(\[|\[\[|case|[A-Za-z_]*=)[^;]*\$\?/ || st[s + 1] ~ ("^[ \t]*(if|elif)[ \t]+![ \t]*jq[^<]*<<<[ \t]*\"?\\$\\{?" a "[^A-Za-z0-9_]") || st[s + 1] ~ ("^[ \t]*\\[\\[?[ \t]+-[nz][ \t]+\"?\\$\\{?" a "[^A-Za-z0-9_]"))) checked = 1
            state[a] = checked ? "checked" : "capture"
            # A `|| v=` fallback answers a failed read on purpose, so it is no bare capture,
            # but a later `jq -e` over it still needs the validation.
            bare = !(fallback && !checked)
            inner = rest; sub(/^"?\$\([ \t]*/, "", inner)
            while (inner ~ /^(command|builtin|env)[ \t]/) sub(/^[a-z]+[ \t]+/, "", inner)
            if (!checked && bare && !marked && inner ~ /^(gh|api|t3|ffmpeg|nvidia-smi)([ \t)]|$)/)
              printf "%s:%d: bare capture of %s with no `||` or status check; check the exit status, or mark a read whose failure is the answer with a `# read-checked: <reason>` marker\n", FILENAME, ln[s], inner ~ /^gh/ ? "gh" : substr(inner, 1, index(inner, " ") ? index(inner, " ") - 1 : length(inner))
          } else state[a] = "other"
        }
        if (code ~ /^[ \t]*(if|elif)[ \t]+!?[ \t]*jq[ \t]+(-[A-Za-z]+[ \t]+)*(-[A-Za-z]*e[A-Za-z]*|--exit-status)[ \t]/ && match(code, /<<<[ \t]*"?\$\{?[A-Za-z_][A-Za-z0-9_]*/)) {
          v = substr(code, RSTART, RLENGTH); sub(/^<<<[ \t]*"?\$\{?/, "", v)
          if (code ~ /^[ \t]*(if|elif)[ \t]+![ \t]*jq/) { if (state[v] == "capture") state[v] = "validated"; continue }
          if (state[v] == "capture" && !marked)
            printf "%s:%d: jq -e reads $%s, a capture whose status was never checked: jq exits 2 or 5 on an empty or broken capture and the else branch reads that as no; check the capture first, or mark it with a `# read-checked: <reason>` marker\n", FILENAME, ln[s], v
        }
      }
    }
  ' "$f") || { printf 'cannot read %s\n' "$f" >&2; exit 2; }
  if [ -n "$out" ]; then printf '%s\n' "$out"; rc=1; fi
done
exit $rc
