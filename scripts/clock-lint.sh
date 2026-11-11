#!/usr/bin/env bash
# The clock rule of docs/contributing/standards/tests.md, linted: a test that
# asserts on a time reads the clock only through a `date` stub it controls, and
# an elapsed-time bound under the coding standards' clock exception is marked.
# Two tests built a fixture from the real clock (#1090, #1135) because nothing
# looked. `scripts/check.sh full` runs this as its `clock` row, and the edit
# rung runs it on an edited test file through the `clock-lint` pre-commit hook.
#
#   scripts/clock-lint.sh [<test file>...]     default: every tests/*.sh
#
# A line fails when it calls `date` and the call reads the current time: no
# `-d`/`--date`/`-r` argument, or a `-d` value relative to now (`2 hours ago`,
# `now`, `yesterday`). A conversion of a fixed time (`-d @<epoch>`, `-d <literal
# date>`, a variable) and a pass-through (`date "$@"`) are not reads. Exempt:
# a file that defines a `date` stub (a heredoc written to a file named `date`,
# or a `date()` function), whose reads go through it; the body of a quoted
# heredoc, a fixture script that runs later; and a line carrying
# `# clock-exception: <reason>`, for an elapsed-time bound proving a watchdog or
# timeout fired, which reads the real clock on purpose. The reason is required.
#
# stdout: one `<file>:<line>: ...` line per violation, nothing when clean
# exit: 0 clean · 1 a violation · 2 tooling
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

if [ "$#" -eq 0 ]; then
  set -- tests/*.sh
fi
for f in "$@"; do [ -f "$f" ] || { printf 'not a file: %s\n' "$f" >&2; exit 2; }; done

rc=0
for f in "$@"; do
  # Per file, because the stub exemption is the file's.
  stubbed=$(awk '
    /^[ \t]*date[ \t]*\(\)/ { print 1; exit }
    /<<-?[ \t]*["\047]?[A-Za-z_]+["\047]?/ && /(^|[ \t>"\/])date["]?[ \t]*<</ { print 1; exit }
  ' "$f")
  out=$(awk -v stub="${stubbed:-0}" '
    function cutargs(s,   i, c) {
      for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c ~ /[)`;|&<>]/) return substr(s, 1, i - 1) }
      return s
    }
    function cmdpos(p,   q) {
      # Inside single quotes it is text, and `\$(` is text a later shell expands.
      q = p; gsub(/[^\047]/, "", q)
      if (length(q) % 2 == 1 || p ~ /\\\$\($/) return 0
      sub(/[ \t]+$/, "", p)
      if (p == "") return 1
      if (p ~ /(\$\(|[(`;|&{!])$/) return 1
      if (p ~ /(^|[ \t])(then|do|else|exec)$/) return 1
      return 0
    }
    BEGIN { end = "" }
    {
      line = $0
      if (end != "") { if (line ~ ("^[ \t]*" end "[ \t]*$")) end = ""; next }
      if (line ~ /<<-?[ \t]*["\047][A-Za-z_]+["\047]/) {
        h = line; sub(/^.*<<-?[ \t]*["\047]/, "", h); sub(/["\047].*$/, "", h); end = h
      }
      if (line ~ /^[ \t]*#/) next
      mark = (line ~ /#[ \t]*clock-exception:[ \t]*[^ \t]/)
      code = line; sub(/[ \t]#.*$/, "", code)
      rest = code; off = 0
      while (match(rest, /(^|[^A-Za-z0-9_.\/-])date([^A-Za-z0-9_.=\/-]|$)/)) {
        s = RSTART; l = RLENGTH
        d = (substr(rest, s, 1) == "d") ? s : s + 1
        pre = substr(code, 1, off + d - 1)
        args = cutargs(substr(rest, d + 4))
        rest = substr(rest, s + l); off += s + l - 1
        if (!cmdpos(pre)) continue
        if (args ~ /\$[@*]/) continue
        reads = 1
        if (args ~ /(^|[ \t])(-[A-Za-z]*d|--date|-r|--reference)([ \t=]|$)/) {
          # The name of a variable is no word of the date: `-d "$now"` converts a time
          # the test already holds.
          rel = args; gsub(/\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*/, "", rel)
          reads = (rel ~ /(^|[^A-Za-z0-9_])(ago|now|today|yesterday|tomorrow|next|last|hence)([^A-Za-z0-9_]|$)/)
        }
        if (reads && !mark && !stub) printf "%s:%d: reads the current time with date; put a date stub on PATH, or mark an elapsed-time bound with a trailing `# clock-exception: <reason>`\n", FILENAME, NR
      }
    }
  ' "$f") || { printf 'cannot read %s\n' "$f" >&2; exit 2; }
  if [ -n "$out" ]; then printf '%s\n' "$out"; rc=1; fi
done
exit $rc
