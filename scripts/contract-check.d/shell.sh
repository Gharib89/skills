# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # variables set by the sourcing script
# Checks 14 to 16 of scripts/contract-check.sh, sourced by it: they share its variables.
# 14. Markdown that invokes a mechanic names the flags the call requires. A code
# span opening with `<mechanic> ` is an invocation, and one that leaves out a
# required flag teaches a call the mechanic refuses: ship's phase 7 wrote
# `update-pr-body --section` for a call that also needs `--body-file`. The
# required flags are the usage line's own, outside [...]; a `( --a | --b )`
# group is satisfied by either. A mechanic with top-level alternatives
# (`run-file`) has no one flag set to hold. Fenced blocks are samples, so they
# are skipped, and a CHANGELOG records what once was true.
: > "$work/required"
for path in "$dir"/*.sh; do
  m=$(basename "$path" .sh)
  [ -f "$work/$m.usage" ] || continue
  utail=$(tail_of "$m" "$(cat "$work/$m.usage")")
  [ "$(usage_alts "$utail" | wc -l)" -eq 1 ] || continue
  reqs=$(required_flags "$utail" | tr '\n' ' ')
  [ -n "$reqs" ] && printf '%s\t%s\n' "$m" "$reqs" >> "$work/required"
done
if [ -s "$work/required" ]; then
  find "$skills" -name '*.md' ! -name CHANGELOG.md | sort | tr '\n' '\0' | xargs -0 awk -v reqfile="$work/required" '
      BEGIN { while ((getline l < reqfile) > 0) { split(l, p, "\t"); req[p[1]] = p[2] } }
      FNR == 1 { fence = ""; flen = 0 }
      {
        if (match($0, /^ *(```+|~~~+)/)) {
          t = substr($0, RSTART, RLENGTH); gsub(/ /, "", t)
          if (fence == "") { fence = substr(t, 1, 1); flen = length(t); next }
          if (substr(t, 1, 1) == fence && length(t) >= flen && $0 ~ /^ *[`~]+ *$/) { fence = ""; next }
        }
        if (fence != "") next
        line = $0
        while ((i = index(line, "`")) > 0) {
          k = 0; while (substr(line, i + k, 1) == "`") k++
          rest = substr(line, i + k); delim = ""; for (z = 0; z < k; z++) delim = delim "`"
          j = index(rest, delim)
          if (j == 0) break
          span = substr(rest, 1, j - 1)
          line = substr(rest, j + k)
          sub(/^ +/, "", span)
          for (m in req) {
            if (index(span, m " ") != 1) continue
            n = split(req[m], r, " ")
            for (x = 1; x <= n; x++) {
              if (r[x] == "") continue
              na = split(r[x], alt, "|"); ok = 0
              for (y = 1; y <= na; y++) if (index(span, alt[y]) > 0) ok = 1
              if (!ok) { gsub(/\|/, " or ", r[x]); printf "%s:%d: `%s` lacks %s from %s\047s usage line\n", FILENAME, FNR, span, r[x], m }
            }
          }
        }
      }' > "$work/doc-hits"
  if [ -s "$work/doc-hits" ]; then cat "$work/doc-hits"; rc=1; fi
fi

# 15. Three habits grep can hold, over every shell file under the skills tree,
# on lines that are not comments (a line opening with `#` is prose, as in
# check 3).
# (a) curl with no --max-time on its logical line, `\` continuations joined: a
#     hung connection hangs the caller, and a mechanic or hook has no human to
#     interrupt it. `command -v curl` and a name ending in curl (`_curl`) are
#     not invocations.
# (b) a `bash -c`, `sh -c` or `eval` with no stdin redirect (a `<`, `<<` or
#     `<<<` outside a `$(...)`, and not a `<(`) inside a `while read` loop
#     whose `done` takes a redirect: a file, a process substitution, a heredoc
#     or a here-string. A loop fed by a pipe, or written on one line, is not
#     reached, since the scan anchors on a `done` line. The rule covers command
#     strings on purpose: a direct filter that reads stdin (`cat`, `sed`) is
#     visible in the loop, while a command string hides whether it reads stdin. Unredirected, the
#     command inherits the loop's stdin and drains it: measured on Bash 3.2.57
#     and 5.3.9, an unredirected `bash -c 'cat'` or `eval` ran 1 of 3 rows, and
#     `</dev/null` ran all 3.
# (c) a three-backtick fence pattern outside the SHIP_AWK_FENCE definition in
#     _lib.sh, the one fence grammar: a second, hand-rolled one, even elsewhere
#     in _lib.sh, is how a four-backtick fence ended up closed by a
#     three-backtick line.
find "$skills" -name '*.sh' | sort | tr '\n' '\0' | xargs -0 awk -v lib="$skills/ship/scripts/_lib.sh" '
    function indent(s) { match(s, /^[ \t]*/); return substr(s, 1, RLENGTH) }
    FNR == 1 { delete L; acc = ""; start = 0; def = 0 }
    { L[FNR] = $0 }
    FILENAME == lib && /^readonly SHIP_AWK_FENCE=/ { def = FNR }
    $0 ~ /^[ \t]*#/ { next }
    {
      if (!def && (index($0, "```") || $0 ~ /(\\`){3}/ || index($0, "`{3")))
        printf "%s:%d: a hand-rolled fence pattern; use SHIP_AWK_FENCE from _lib.sh\n", FILENAME, FNR
      line = $0
      if (acc == "") start = FNR
      if (line ~ /\\$/) { sub(/\\$/, "", line); acc = acc line " "; }
      else {
        cmd = acc line; acc = ""
        gsub(/(command|type|which|hash)( +-[a-zA-Z]+)* +curl/, "", cmd)
        if (cmd ~ /(^|[^A-Za-z0-9_."\047-])curl([^A-Za-z0-9_]|$)/ && cmd !~ /--max-time/)
          printf "%s:%d: curl without --max-time; a hung download hangs the caller with it\n", FILENAME, start
      }
      if ($0 ~ /^[ \t]*done[ \t]*</) {
        ind = indent($0); open = 0
        for (k = FNR - 1; k >= 1; k--) {
          if (L[k] ~ /^[ \t]*#/ || indent(L[k]) != ind) continue
          if (L[k] ~ /^[ \t]*(while|until|for)[ \t]/) { open = (L[k] ~ /^[ \t]*while .*read/) ? k : 0; break }
          if (L[k] ~ /^[ \t]*done/) break
        }
        for (k = open + 1; open && k < FNR; k++) {
          s = L[k]; gsub(/\$\([^()]*\)/, "", s)
          if (s ~ /^[ \t]*#/ || s ~ /<([^(]|$)/) continue
          if (match(L[k], /(^|[^A-Za-z0-9_])(bash -c|sh -c|eval )/)) {
            c = substr(L[k], RSTART, RLENGTH); gsub(/^[^a-z]+/, "", c); sub(/ +$/, "", c)
            printf "%s:%d: %s inside a while-read loop over redirected input reads the loop\047s stdin; give it </dev/null\n", FILENAME, k, c
          }
        }
      }
      if (def && FNR > def && /\047[ \t]*$/) def = 0
    }' > "$work/shell-hits"
if [ -s "$work/shell-hits" ]; then cat "$work/shell-hits"; rc=1; fi

# 16. No pipe into a quiet grep (`grep -q`, `-Eq`, `-qE`, `-e PAT -q`, `--quiet`,
# `--silent`) in a shell file under the skills tree or an <extra-dir> that sets
# pipefail, on lines that are not comments. `grep -q` exits at its first match,
# the writer dies of SIGPIPE (141) while still writing, and under pipefail the
# pipeline reads as no match: a gate failed open on it in #758. A here-string
# over a captured value makes the verdict depend on the input alone. A pipe at
# the end of a line, or a `\`, continues the command onto the next line; a `|&`
# is a pipe; a flag counts up to the command's next separator; assignments, `env`,
# `command` and the like, and a path before `grep` do not hide it.
files=$(find "$skills" ${extra[@]+"${extra[@]}"} -name '*.sh' | sort) || { printf 'cannot search %s\n' "$skills" >&2; exit 2; }
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -qE '^[[:space:]]*set[[:space:]].*pipefail' "$f"; st=$?
  [ "$st" -le 1 ] || { printf 'cannot read %s\n' "$f" >&2; exit 2; }
  [ "$st" -eq 0 ] || continue
  awk -v f="$f" '
    /^[ \t]*#/ { next }
    {
      if (acc == "") start = FNR
      line = $0
      if (line ~ /\\$/) { sub(/\\$/, "", line); acc = acc line " "; next }
      if (line ~ /[^|]\|&?[ \t]*$/) { acc = acc line " "; next }
      cmd = acc line; acc = ""
      while (match(cmd, /[^|]\|&?[ \t]*(([A-Za-z_][A-Za-z0-9_]*=[^ \t]*|command|builtin|env|exec|time|nice)[ \t]+)*([^ \t]*[/])?(e|f)?grep([ \t]|$)/)) {
        cmd = substr(cmd, RSTART + RLENGTH)
        seg = cmd; sub(/[|;&<>)].*/, "", seg)
        n = split(seg, tok, /[ \t]+/)
        for (i = 1; i <= n && tok[i] != "--"; i++)
          if (tok[i] ~ /^(--quiet|--silent)$/ || tok[i] ~ /^-[A-Za-z]*q/) {
            printf "%s:%d: a pipe into a quiet grep under pipefail fails open on SIGPIPE; read the writer\047s output into a variable and use grep -q PATTERN <<<\"$var\"\n", f, start
            break
          }
      }
    }' "$f" || { printf 'cannot scan %s\n' "$f" >&2; exit 2; }
done <<< "$files" > "$work/pipe-hits"
if [ -s "$work/pipe-hits" ]; then cat "$work/pipe-hits"; rc=1; fi

