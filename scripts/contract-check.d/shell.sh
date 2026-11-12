# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # variables set by the sourcing script
# Checks 14 to 16 of scripts/contract-check.sh, sourced by it: they share its variables.
# 14. Markdown that invokes a mechanic names the flags and value forms the call
# requires, wherever the call is written, because a recipe that exits 2 as
# written teaches a call the mechanic refuses: ship's phase 7 wrote
# `update-pr-body --section` for a call that also needs `--body-file`.
#   Where a call is read:
#   - a code span whose first word names a mechanic: bare (`merge`), with `.sh`
#     (`quota.sh`) or with a path to the script (`scripts/quota.sh`); a span may
#     run over a line break;
#   - a line of a fenced block that is an instruction to run, which is a fence
#     whose language is sh, bash, shell, zsh or console, with `\` continuations
#     joined and the call cut at a pipe, `&&`, `||`, `;` or a redirect. Any
#     other fence (none, text, json, diff) is a sample of output and is skipped.
#   - a call names a mechanic and gives it arguments: the mechanic alone, or with
#     only its verb (`run-file gate clean`), or asked `--help`, names the tool and is not read;
#   - a deliberate sample is skipped by a line holding `contract-check: sample`
#     (all spans on that line), or by such a line directly above a fence.
#   - a CHANGELOG records what once was true, so it is skipped.
#   What a call owes: the usage line's own required flags, outside [...]; a
#   `( --a | --b )` group is satisfied by either. A mechanic with top-level
#   alternatives (`run-file`, `ledger`) is read per alternative, the one a call
#   names by its verb, or by its first required flag where it has no verb; flags
#   written before the first alternative's verb (`ledger --ledger <file> add|...`)
#   belong to every alternative. A `<json>` slot takes a JSON value: a
#   `<placeholder>`, a number, true, false, null, a `{`/`[` structure or a
#   string quoted for the shell with its own quotes inside (`'"main"'`), so an
#   unquoted word is refused.
# alt_verb <alt>: the 1-based positions "first last" of the up to two words at
# bracket depth 0 that name the alternative (`gate clean`, `set`, `add|adopt`),
# or nothing. A word straight after a flag is that flag's value (`--job text`),
# not a verb; after a <slot> it is one (`--ledger <file> add`).
alt_verb() {
  printf '%s\n' "$1" | awk '{
    d = 0; n = split($0, w, " "); f = 0
    for (i = 1; i <= n; i++) {
      t = w[i]
      if (d == 0 && t ~ /^[a-z][a-z0-9-]*(\|[a-z0-9-]+)*$/ && w[i - 1] !~ /^--/) { if (!f) f = i; if (i - f < 2) l = i; continue }
      if (f) break
      if (d == 0 && t !~ /^[-<"\[(]/) break
      for (j = 1; j <= length(t); j++) { c = substr(t, j, 1); if (c == "[" || c == "(") d++; else if (c == "]" || c == ")") d-- }
    }
    if (f) print f, l }'
}
# json_slot <alt> <verb position>: which word after the verb (after the mechanic
# when there is none) is the alternative's `<json>` slot, up to its first flag.
json_slot() {
  printf '%s\n' "$1" | awk -v v="${2:-0}" '{
    n = split($0, w, " "); k = 0
    for (i = v + 1; i <= n; i++) { if (w[i] ~ /^[-\[(]/) break; k++; if (w[i] == "<json>") { print k; exit } } }'
}
: > "$work/required"
for path in "$dir"/*.sh; do
  m=$(basename "$path" .sh)
  [ -f "$work/$m.usage" ] || continue
  utail=$(tail_of "$m" "$(cat "$work/$m.usage")")
  alts=$(usage_alts "$utail")
  multi=0; [ "$(printf '%s\n' "$alts" | wc -l)" -gt 1 ] && multi=1
  lead=""
  while IFS= read -r a; do
    a=${a#"$m "}
    # A line that is prose about the flags (`<line>, each taking --file or --issue`) is no call to hold.
    case $a in *', '*) continue ;; esac
    read -r vf vl <<<"$(alt_verb "$a")"; sel=""
    if [ "$multi" -eq 1 ]; then
      if [ -n "$vf" ]; then sel=$(printf '%s\n' "$a" | awk -v f="$vf" -v l="$vl" '{s = $f; for (k = f + 1; k <= l; k++) s = s " " $k; print s}')
      else sel=$(required_flags "$a" | head -1); fi
      [ -n "$sel" ] || continue
    fi
    if [ "$multi" -eq 1 ] && [ -z "$lead" ] && [ -n "$vf" ]; then
      lead=$(required_flags "$(printf '%s\n' "$a" | awk -v i="$vf" '{s = ""; for (k = 1; k < i; k++) s = s $k " "; print s}')" | tr '\n' ' ')
    fi
    reqs=$(required_flags "$a" | tr '\n' ' ')
    printf '%s\t%s\t%s\t%s\n' "$m" "$sel" "$reqs" "$(json_slot "$a" "${vl:-0}")" >> "$work/required"
  done <<EOA
$alts
EOA
  # `lead` is known only after the first alternative: add it to every row of this
  # mechanic, which is how a global flag reaches the alternatives after the first.
  if [ -n "$lead" ]; then
    awk -F'\t' -v OFS='\t' -v m="$m" -v lead="$lead" '$1 == m { $3 = $3 " " lead } { print }' "$work/required" > "$work/required.new" && mv "$work/required.new" "$work/required"
  fi
done
# A mechanic with no required flag and no <json> slot owes nothing.
awk -F'\t' '$3 ~ /[^ ]/ || $4 != ""' "$work/required" > "$work/required.new" && mv "$work/required.new" "$work/required"
if [ -s "$work/required" ]; then
  find "$skills" -name '*.md' ! -name CHANGELOG.md | sort | tr '\n' '\0' | xargs -0 awk -v reqfile="$work/required" '
      function mech(tok,   b) {
        sub(/^[$("\047`]+/, "", tok)
        if (tok ~ /\//) { if (tok !~ /\.sh$/) return ""; sub(/.*\//, "", tok) }
        sub(/\.sh$/, "", tok)
        return (tok in known) ? tok : ""
      }
      function has(padded, part) { return index(padded, " " part " ") > 0 || (part ~ /^--/ && index(padded, " " part "=") > 0) }
      function jsonok(t) {
        if (t ~ /^</ || t ~ /^(-?[0-9]+(\.[0-9]+)?|true|false|null)$/ || t ~ /^[\[{]/) return 1
        if (t ~ /^\047["\[{0-9]/ || t ~ /^"\\"/) return 1
        return 0
      }
      function check(call, ln,   toks, nt, m, padded, r, sel, np, q, hit, s, rq, nq, x, na, alt, y, ok, base, jt, w, any, kt, lw) {
        nt = split(call, toks, " "); m = mech(toks[1]); padded = " " call " "
        for (r = 1; r <= nr; r++) {
          if (rm[r] != m) continue
          sel = rsel[r]; base = 1
          if (sel != "") {
            np = split(sel, q, "|"); hit = 0
            for (s = 1; s <= np; s++) if (has(padded, q[s])) { hit = 1; lw = q[s]; sub(/.* /, "", lw); if (q[s] !~ /^--/) for (kt = 1; kt <= nt; kt++) if (toks[kt] == lw) base = kt }
            if (!hit) continue
          }
          if (nt == base || has(padded, "--help")) continue
          nq = split(rreq[r], rq, " ")
          for (x = 1; x <= nq; x++) {
            if (rq[x] == "" || (rq[x] in seen_here)) continue
            seen_here[rq[x]] = 1
            na = split(rq[x], alt, "|"); ok = 0
            for (y = 1; y <= na; y++) if (has(padded, alt[y])) ok = 1
            if (!ok) { w = rq[x]; gsub(/\|/, " or ", w); printf "%s:%d: `%s` lacks %s from %s\047s usage line\n", curfile, ln, call, w, m }
          }
          delete seen_here
          if (rjson[r] != "" && (jt = toks[base + rjson[r]]) != "" && !jsonok(jt))
            printf "%s:%d: `%s` gives %s where %s\047s usage line takes a <json> value; quote a string as \047\"text\"\047\n", curfile, ln, call, jt, m
        }
      }
      function spans(txt, pos0,   i, k, rest, delim, z, j, span, line, off, n) {
        line = txt; off = 0
        while ((i = index(line, "`")) > 0) {
          k = 0; while (substr(line, i + k, 1) == "`") k++
          rest = substr(line, i + k); delim = ""; for (z = 0; z < k; z++) delim = delim "`"
          j = index(rest, delim)
          if (j == 0) break
          span = substr(rest, 1, j - 1)
          sub(/^ +/, "", span)
          if (index(span, " ") > 0 && mech(substr(span, 1, index(span, " ") - 1)) != "") {
            at = off + i; n = 1; while (n < pn && poff[n + 1] <= at) n++
            check(span, pline[n])
          }
          off += i + 2 * k + j - 2; line = substr(rest, j + k)
        }
      }
      function flush() { if (ptxt != "") spans(ptxt); ptxt = ""; pn = 0 }
      function addline(s) { if (ptxt != "") ptxt = ptxt " "; pn++; poff[pn] = length(ptxt) + 1; pline[pn] = FNR; ptxt = ptxt s }
      function runline(s,   toks, nt, i, call) {
        if (s ~ /^ *#/) return
        nt = split(s, toks, " ")
        for (i = 1; i <= nt; i++) if (mech(toks[i]) != "") break
        if (i > nt) return
        call = toks[i]
        for (i = i + 1; i <= nt; i++) {
          if (toks[i] ~ /^(\||\|\||&&|;|&)$/ || toks[i] ~ /^[0-9]*>/ || (toks[i] ~ /^</ && toks[i] !~ />$/) || toks[i] ~ /;$/) break
          call = call " " toks[i]
        }
        sub(/[)]+$/, "", call)
        check(call, fstart)
      }
      BEGIN {
        while ((getline l < reqfile) > 0) { n = split(l, p, "\t"); nr++; rm[nr] = p[1]; rsel[nr] = p[2]; rreq[nr] = p[3]; rjson[nr] = p[4]; known[p[1]] = 1 }
        MARK = "contract-check: sample"
      }
      FNR == 1 { flush(); curfile = FILENAME; fence = ""; flen = 0; fcheck = 0; sample = 0; facc = "" }
      {
        if (match($0, /^ *(```+|~~~+)/)) {
          t = substr($0, RSTART, RLENGTH); gsub(/ /, "", t)
          if (fence == "") {
            flush()
            fence = substr(t, 1, 1); flen = length(t)
            info = tolower(substr($0, RSTART + RLENGTH)); sub(/^ +/, "", info); sub(/[ \t{].*/, "", info)
            fcheck = (info ~ /^(sh|bash|shell|zsh|console)$/) && !sample; sample = 0; facc = ""
            next
          }
          if (substr(t, 1, 1) == fence && length(t) >= flen && $0 ~ /^ *[`~]+ *$/) { fence = ""; fcheck = 0; facc = ""; next }
        }
        if (fence != "") {
          if (!fcheck) next
          line = $0; sub(/^ *(\$ )?/, "", line)
          if (facc == "") fstart = FNR
          if (line ~ /\\$/) { sub(/\\$/, "", line); facc = facc line " "; next }
          runline(facc line); facc = ""
          next
        }
        if (index($0, MARK)) { sample = 1; addline(""); next }
        sample = 0
        if ($0 ~ /^[ \t]*$/ || $0 ~ /^#/ || $0 ~ /^ *([-*+]|[0-9]+[.)]) / || $0 ~ /^ *\|/) flush()
        if ($0 ~ /^[ \t]*$/) next
        addline($0)
      }
      END { flush() }' > "$work/doc-hits"
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

