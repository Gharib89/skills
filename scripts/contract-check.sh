#!/usr/bin/env bash
# The mechanics' malformed-invocation contract, enforced. Every mechanic reports
# a malformed invocation as {"error": "<usage>"} on stdout with exit 2; the ship
# profile's `## Public surface` names that as a contract, and a mechanic written
# with the pre-#62 `${N:?}` idiom reintroduces exit 1 with a bare shell
# diagnostic and no JSON. `scripts/check.sh full` runs this as its `contract`
# row, which scripts/local-gate.sh reports under the same name.
#
#   scripts/contract-check.sh [<scripts-dir> [<skills-dir>]]
#
# Reaches no host: every mechanic's usage guard fires before it loads the host
# adapter, so a no-argument invocation makes no network call. Keep a new
# mechanic's guard there. Check 2 cannot police that placement: a late guard
# still exits 2 with an error object, because `ship_load_host` reports its own
# failure in exactly that shape.
#
# Check 3 traverses the whole skills tree rather than the mechanics alone, so it
# takes its own directory argument.
#
# Checks 4 and 5 invoke a mechanic with arguments. An unguarded mechanic makes
# check 4 reach the host once: that failure is the finding, and the ids it sends
# cannot exist. Check 5 has the wider reach of the two, because check 4 skips the
# mechanics that take no positional and check 5 exempts nobody; a mechanic whose
# `ship_help` landed after `ship_load_host` is what makes it load an adapter.
#
# Check 5 is the --help contract: a run asks a mechanic what its flags and its
# answer are by running it, so the answer has to be the usage line then its
# `stdout:` field names, on stdout, exit 0.
#
# Check 6 reads the skills tree too, every file in it: SHIP_HOST_ADAPTER has
# one reader, `ship_load_host` in `_lib.sh`, and a mention anywhere else is a
# second.
#
# Checks 7 to 9 read setup-harness, when the skills tree carries it: its
# catalog entries' format, the two profile-template lines setup-skills parses
# and the harness schema number's four places.
#
# Check 10 reads two sentences of ship's prose that nothing else holds: phase
# 4's instruction that an axis reads the Local gate's JSON rather than running
# the suite, and context discipline's one-reference-file-per-call rule. Each is
# matched as a substring of the file with its line wraps joined, so the same
# words turned to the opposite meaning ("and also runs") do not pass.
#
# Checks 11 to 14 compare a mechanic's usage line, as `--help` prints it, with
# the rest of what describes it:
# 11  the header synopsis names the same flags and leading slots;
# 12  every flag that takes a value refuses a leading-dash value with the usage
#     line;
# 13  every host failure, driven through the Host fake, prints one JSON object;
# 14  Markdown that invokes a mechanic in a code span names its required flags.
# Check 15 greps every shell file for three habits that fail silently: a curl
# with no time limit, a command in a redirect-fed read loop that drains the loop's
# input, and a fence pattern written by hand instead of SHIP_AWK_FENCE.
#
# stdout: one line per violation, with the offending mechanic or file named
# exit: 0 the contract holds · 1 a violation · 2 tooling
set -uo pipefail
dir=${1:-skills/ship/scripts}
skills=${2:-skills}
[ -d "$dir" ] || { printf 'not a directory: %s\n' "$dir" >&2; exit 2; }
[ -d "$skills" ] || { printf 'not a directory: %s\n' "$skills" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq not installed" >&2; exit 2; }

rc=0

# 1. No positional-parameter error expansion anywhere under the mechanics,
# adapters included: `${2:?msg}` and `${2?msg}` both exit 1 with bash's
# diagnostic on stderr and no JSON.
hits=$(grep -rn '\${[0-9]\{1,\}:\{0,1\}?' "$dir"); st=$?
[ "$st" -le 1 ] || { printf 'cannot search %s\n' "$dir" >&2; exit 2; }
if [ "$st" -eq 0 ]; then
  echo "positional error expansion under $dir; a malformed invocation prints JSON and exits 2:"
  echo "$hits"
  rc=1
fi

# 2. Every mechanic that requires an argument, invoked with none, prints exactly
# one JSON object carrying an `error` key and exits 2. The six listed here take
# no positional, so a bare invocation of one is a real run, not a malformed one.
takes_no_positional=" base-fresh select tooling list-prs prepare dropped-lines "
for path in "$dir"/*.sh; do
  m=$(basename "$path" .sh)
  [ "$m" = _lib ] && continue
  case $takes_no_positional in *" $m "*) continue ;; esac
  out=$(bash "$path" 2>/dev/null); st=$?
  if [ "$st" -ne 2 ]; then
    printf '%s: bare invocation exited %s, expected 2\n' "$m" "$st"
    rc=1
    continue
  fi
  printf '%s' "$out" | jq -se 'length == 1 and (.[0] | type == "object" and has("error"))' >/dev/null 2>&1 \
    || { printf '%s: bare invocation did not print exactly one JSON object with an error key\n' "$m"; rc=1; }
done

# 3. No Bash 4+ construct under the skills tree. A derived copy runs in whatever
# shell a consumer machine provides, macOS's system Bash 3.2 included, and the
# mechanics carry no `set -e`: a mapfile there prints "command not found" and
# execution continues, so the mechanic answers on state it never collected.
# Shell files only, because the prose under skills/ names these constructs
# deliberately. A line whose first non-blank character is `#` is prose too; a
# mention anywhere else on a line is flagged, which is a loud false positive the
# author rewords, never a silent pass.
bash4='(^|[^[:alnum:]_])(mapfile|readarray)([^[:alnum:]_]|$)|(declare|local|typeset)([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*A|\$\{([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*])(\[[^]]*\])?(,|\^)'
raw=$(grep -rnE --include='*.sh' "$bash4" "$skills"); st=$?
[ "$st" -le 1 ] || { printf 'cannot search %s\n' "$skills" >&2; exit 2; }
# The comment exclusion reads the content field rather than the whole line: a
# grep for `#` anywhere in it drops a real violation whose own content happens
# to carry `:12: #`.
hits=$(printf '%s' "$raw" | awk '
  { content = $0; sub(/^[^:]*:[0-9]+:/, "", content); if (content ~ /^[ \t]*#/) next; print }
')
if [ -n "$hits" ]; then
  echo "Bash 4+ construct under $skills; everything a consumer installs targets Bash 3.2, which answers a mapfile with \"command not found\" and carries on, a declare -A with an invalid option, and a case modifier with a bad substitution:"
  echo "$hits"
  rc=1
fi

# 4. Every mechanic that takes a positional id refuses a leading-dash value in
# it, with its own usage line, before it loads the host adapter. Without the
# guard a flag typed where the id belongs is read as the id: `update-pr-body
# --section Review --body-file b.md` asks the host for PR `--section`, and
# `cleanup --x` answered `branch_deleted: true` for a null branch.
#
# Three arities, because no single one catches every mechanic: one `--x` alone
# is answered by a two-positional mechanic's missing-second-positional guard,
# which passes for the wrong reason, and a third dash is what makes a one-
# positional mechanic's flag loop answer `unknown flag` instead of its usage
# line. The assertion is the usage line itself: every mechanic's usage string
# opens with its own name, which is what lets one check cover all of them
# without knowing any mechanic's arity.
#
# `file-issue` joins check 2's exclusions here because it takes no positional
# either; it stays off that list because its own bare invocation *is*
# malformed, so check 2 must keep testing it.
has_no_positional="${takes_no_positional}file-issue "
for path in "$dir"/*.sh; do
  m=$(basename "$path" .sh)
  [ "$m" = _lib ] && continue
  case $has_no_positional in *" $m "*) continue ;; esac
  dashes=()
  for i in 1 2 3; do
    dashes+=(--x)
    out=$(bash "$path" "${dashes[@]}" 2>/dev/null); st=$?
    if [ "$st" -ne 2 ]; then
      printf '%s: %s leading-dash positional(s) exited %s, expected 2\n' "$m" "$i" "$st"
      rc=1
      continue
    fi
    printf '%s' "$out" | jq -se --arg m "$m" 'length == 1 and (.[0] | type == "object" and ((.error // "") | test("^usage: " + $m + "( |$)") and (contains("\n") | not)))' >/dev/null 2>&1 \
      || { printf '%s: %s leading-dash positional(s) did not answer with its own usage line\n' "$m" "$i"; rc=1; }
  done
done

# 5. Every mechanic answers `--help` with its own usage line on stdout, then a
# `stdout:` line naming the fields it answers with (`ship_help` prints both),
# exit 0 and nothing on stderr. No mechanic is exempt, the four that take no
# positional included: a run reads a mechanic's flags and answer by running it,
# and one that has none still answers with its name. update-skills' mechanics
# share `ship_help`, so the same rule holds for them.
#
# Run from a directory with no resolvable origin, which is what makes this check
# police the guard's PLACEMENT where check 2 cannot. A guard after
# `ship_load_host` answers correctly wherever an adapter loads, and the load
# makes no host call, so a check run from the repo cannot see the difference.
# From here it can: a late guard answers `--help` with the adapter's tooling
# error, which is the answer someone asking what the flags are would get on a
# machine that has no origin remote.
err=$(mktemp) || { echo "cannot create a temp file" >&2; exit 2; }
nogit=$(mktemp -d) || { echo "cannot create a temp directory" >&2; exit 2; }
work=$(mktemp -d) || { echo "cannot create a temp directory" >&2; exit 2; }
trap 'rm -f "$err"; rm -rf "$nogit" "$work"' EXIT
for path in "$dir"/*.sh; do
  m=$(basename "$path" .sh)
  [ "$m" = _lib ] && continue
  apath=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
  out=$(cd "$nogit" && bash "$apath" --help 2>"$err"); st=$?
  # stderr is read before the shape checks below return: a mechanic can answer
  # with the wrong line AND talk on stderr, and one report per run per fault is
  # what keeps a fix loop from paying for a second run to see the second fault.
  [ -s "$err" ] && { printf '%s: --help wrote to stderr\n' "$m"; rc=1; }
  if [ "$st" -ne 0 ]; then
    printf '%s: --help exited %s, expected 0\n' "$m" "$st"
    rc=1
    continue
  fi
  # The name ends at the string or at a space: a bare prefix match takes
  # `usage: read-issue-other` for read-issue's own line.
  case $(printf '%s\n' "$out" | sed -n 1p) in
    "usage: $m"|"usage: $m "*) ;;
    *) printf '%s: --help did not print its own usage line on stdout\n' "$m"; rc=1; continue ;;
  esac
  # The usage line, then the stdout field names: the line under it opens with
  # `stdout:`, so a run reads what a mechanic answers by asking it. A case
  # pattern matches across newlines, so the prefix above accepts whatever a
  # mechanic prints under its first line. Reported without `continue`: the
  # comparison with the guard's usage line below is a separate fault.
  case $(printf '%s\n' "$out" | sed -n 2p) in
    stdout:*) ;;
    *) printf '%s: --help did not print a stdout: line after its usage line\n' "$m"; rc=1 ;;
  esac
  out=$(printf '%s\n' "$out" | sed -n 1p)
  # Kept for checks 11 to 14, which compare against what --help printed.
  printf '%s\n' "$out" > "$work/$m.usage"
  # The same line the guards print. Check 4 reads the error path and this one
  # reads the --help path; nothing compares them, so a mechanic can answer
  # --help with a usage line its guards have since outgrown. With the flags out
  # of SKILL.md's table, that answer is the only place a run reads them.
  # `base-fresh` and `select` are the only two with nothing to compare against:
  # their guards answer a bad call `<name> takes no arguments`, not a usage
  # line. Every other mechanic has one, reached by a different call: bare for
  # the two whose bare invocation is itself malformed, one `--x` for `tooling`,
  # whose bare call is a real run, and check 4's three for everything that
  # takes a positional.
  if [ "$m" != base-fresh ] && [ "$m" != select ]; then
    case $m in
      file-issue|list-prs) want=$(bash "$path" 2>/dev/null | jq -r '.error // ""') ;;
      tooling)             want=$(bash "$path" --x 2>/dev/null | jq -r '.error // ""') ;;
      *)                   want=$(bash "$path" --x --x --x 2>/dev/null | jq -r '.error // ""') ;;
    esac
    [ "$out" = "$want" ] || { printf '%s: --help and the usage guard print different lines\n' "$m"; rc=1; }
  fi
done

# 6. SHIP_HOST_ADAPTER is read by `ship_load_host` and nowhere else under the
# skills tree. It swaps the host adapter for whatever file it names, which is
# the test suite's Host fake and nothing a consumer should ever reach, so a
# second reader is a mechanic that can be pointed off its host. Every file,
# prose included: a doc teaching the variable is how a second reader starts.
raw=$(grep -rn 'SHIP_HOST_ADAPTER' "$skills"); st=$?
[ "$st" -le 1 ] || { printf 'cannot search %s\n' "$skills" >&2; exit 2; }
hits=$(printf '%s' "$raw" | awk -F: -v lib="$skills/ship/scripts/_lib.sh" '$1 != lib')
if [ -n "$hits" ]; then
  echo "SHIP_HOST_ADAPTER outside $skills/ship/scripts/_lib.sh; it is test-only, and _lib.sh is its one reader:"
  echo "$hits"
  rc=1
fi

# 7. Every setup-harness catalog entry keeps the entry format its README fixes:
# `## Signals` first, its labels per kind, roles from the fixed set, and every
# `###` tool block carrying every required label. Detection reads only the
# Signals blocks and a run reads the rest by label, so an entry missing one is
# a stack the skill silently half-knows. A `Route:` carries its `Blocked:`
# clause, so a run can tell "nothing is blocked" from "nobody looked". A file
# kind takes no turn rung (it has no project to typecheck or test), and only a
# file kind is claimed by Names: or Paths:, and only a stack carries Library:.
# A tool's Files: is a subset of the entry's Extensions:, since it narrows the
# files the entry claims. Browser
# and public-API tools run on `full` only, and a language server sits on no
# rung, takes no hook and is `Local-only:` with its reason, because it answers
# Claude's `LSP` calls rather than a check and no cloud session starts one;
# `Settings:` is its vendored `.lsp.json` key, so no other tool carries one.
harness=$skills/setup-harness
if [ -d "$harness/catalog" ]; then
  for entry in "$harness"/catalog/*.md; do
    [ "${entry##*/}" = README.md ] && continue
    awk -v f="$entry" '
    function bad(m) { print "catalog " f ": " m; rc = 1 }
    function close_tool(  i) {
      if (tool == "") return
      for (i = 1; i <= nt; i++) if (!(tl[i] in got)) bad("### " tool ": missing " tl[i] ":")
      if (role == "language server" && !("Local-only" in got)) bad("### " tool ": a language server is Local-only:")
      tool = ""; delete got
    }
    function close_signals(  i, n, want) {
      if (!signals) return
      want = kind == "file kind" ? "Kind|Names|Paths|Extensions|Shebangs" : "Kind|Manifest|Lockfile|Workspace|Extensions|Shebangs|Runtime version|Library"
      n = split(want, w, "|")
      for (i = 1; i <= n; i++) if (!(w[i] in sig)) bad("## Signals: missing " w[i] ":")
      if (kind != "stack" && kind != "file kind") bad("## Signals: Kind: want stack or file kind, got " kind)
      if (kind == "stack") { if ("Names" in sig) bad("## Signals: Names: is a file kind\047s"); if ("Paths" in sig) bad("## Signals: Paths: is a file kind\047s") }
      if (kind == "file kind" && ("Library" in sig)) bad("## Signals: Library: is a stack\047s")
      signals = 0
    }
    BEGIN {
      nt = split("Publisher|Tier|Evidence|Rung|Run|Hook|Pin|Route|Constraints|Traps", tl, "|")
      roles = "|lint|format|typecheck|test runner|affected tests|language server|browser|public API|"
    }
    /^## / {
      close_tool(); close_signals()
      role = substr($0, 4)
      if (!headings++) { if (role == "Signals") signals = 1; else bad("first ## heading is not ## Signals"); next }
      if (index(roles, "|" role "|") == 0) bad("## " role ": not a role")
      else if (kind == "file kind" && role != "lint" && role != "format") bad("## " role ": a file kind carries lint and format only")
      next
    }
    /^### / { close_tool(); tool = substr($0, 5); next }
    /^[A-Z][A-Za-z -]*: / || /^[A-Z][A-Za-z -]*:$/ {
      label = substr($0, 1, index($0, ":") - 1); v = substr($0, length(label) + 3)
      if (signals) { sig[label] = 1; if (label == "Kind") kind = v; if (label == "Extensions") exts = " " v " "; next }
      if (tool == "") next
      got[label] = 1
      if (label == "Route" && v != "None." && v !~ /^`[^`]+`; Blocked: /) bad("### " tool ": Route: want `<install>`; Blocked: <routes> | None., or None.")
      if (label == "Hook" && role == "language server" && v != "None.") bad("### " tool ": a language server takes Hook: None.")
      if (label == "Hook" && role != "language server" && v == "None.") bad("### " tool ": Hook: None. is for a language server only")
      if (label == "Local-only" && v == "") bad("### " tool ": Local-only: wants its reason")
      if (label == "Settings" && role != "language server") bad("### " tool ": Settings: is for a language server only")
      if (label == "Files") { n = split(v, fx, " "); for (i = 1; i <= n; i++) if (index(exts, " " fx[i] " ") == 0) bad("### " tool ": Files: " fx[i] " is not in Extensions:") }
      if (label != "Rung") next
      if (role == "language server") { if (v != "None.") bad("### " tool ": a language server takes Rung: None.") }
      else if (v != "edit" && v != "turn" && v != "full") bad("### " tool ": Rung: want edit, turn or full, got " v)
      else if (kind == "file kind" && v == "turn") bad("### " tool ": a file kind takes no turn rung")
      else if ((role == "browser" || role == "public API") && v != "full") bad("### " tool ": " role " is full only")
    }
    END { close_tool(); close_signals(); if (!headings) bad("first ## heading is not ## Signals"); exit rc }
    ' "$entry" || rc=1
  done
fi

# 8. setup-skills reads two lines of a harness profile with no schema check,
# in its harness detection and in its cloud bootstrap template, `Location:`
# under `## Check entry point` and `Setup:` under `## Cloud`, so they are
# frozen across every harness schema:
# renaming either is a major of both skills in one PR. The profile template is
# where a rename would start.
if [ -d "$harness" ]; then
  tmpl=$harness/templates/harness-profile.md
  for pair in "Check entry point:Location" "Cloud:Setup"; do
    awk -v h="## ${pair%%:*}" -v l="${pair#*:}: " '
      /^## / { in_h = ($0 == h); next }
      in_h && index($0, l) == 1 { found = 1 }
      END { exit !found }' "$tmpl" 2>/dev/null \
      || { printf 'harness profile template: ## %s has no %s: line\n' "${pair%%:*}" "${pair#*:}"; rc=1; }
  done
fi

# 9. The harness schema number sits in four places, moved together by the
# bump rule in harness-schema.md: the skill's metadata.harness-schema, the
# template's Schema: line, the checker's schema= literal and the doc's own
# `## Schema <n>` entry. One moved alone ships a template its own checker
# refuses, or a re-run that migrates by an entry that is not there. Each read
# takes the first match before any body heading, as profile-schema-check.sh
# does, and a file it cannot read is tooling rather than drift.
if [ -d "$harness" ]; then
  doc=$harness/harness-schema.md
  meta=$(awk '/^# /{exit} /^  harness-schema: /{print $2; exit}' "$harness/SKILL.md") \
    || { printf 'cannot read %s\n' "$harness/SKILL.md" >&2; exit 2; }
  line=$(awk '/^## /{exit} /^Schema: /{print $2; exit}' "$harness/templates/harness-profile.md") \
    || { printf 'cannot read %s\n' "$harness/templates/harness-profile.md" >&2; exit 2; }
  lit=$(awk -F= '/^schema=/{print $2; exit}' "$harness/scripts/harness-profile-check.sh") \
    || { printf 'cannot read %s\n' "$harness/scripts/harness-profile-check.sh" >&2; exit 2; }
  grep -qxF "## Schema $meta" "$doc"; st=$?
  [ "$st" -le 1 ] || { printf 'cannot search %s\n' "$doc" >&2; exit 2; }
  entry=missing
  [ "$st" -eq 0 ] && entry=present
  if [ -z "$meta" ] || [ "$meta" != "$line" ] || [ "$meta" != "$lit" ] || [ "$entry" = missing ]; then
    printf "harness schema disagrees: SKILL.md metadata.harness-schema %s, templates/harness-profile.md Schema: %s, scripts/harness-profile-check.sh schema=%s, harness-schema.md entry '## Schema %s' %s\n" \
      "${meta:-none}" "${line:-none}" "${lit:-none}" "${meta:-none}" "$entry"
    rc=1
  fi
fi

# 10. The two sentences above. A tree with no ship skill has nothing to hold.
# Whitespace is squeezed first, because the prose is wrapped at 80 columns.
# require_sentence <file> <sentence> <violation>: the file must contain the
# sentence, whitespace-flattened; a file that cannot be read is tooling.
require_sentence() {
  local flat
  flat=$(tr '\n' ' ' < "$1" | tr -s ' ') || { printf 'cannot read %s\n' "$1" >&2; exit 2; }
  case $flat in *"$2"*) ;; *) printf '%s: %s\n' "$1" "$3"; rc=1 ;; esac
}
if [ -f "$skills/ship/SKILL.md" ]; then
  require_sentence "$skills/ship/SKILL.md" \
    "the Local gate runs later in the run, so the axis reads the gate's JSON and never runs \`check.sh full\` or the suite itself" \
    "phase 4 must tell each axis the Local gate runs later, so it reads the gate's JSON and never runs check.sh full or the suite"
fi
if [ -f "$skills/ship/reference/context-discipline.md" ]; then
  require_sentence "$skills/ship/reference/context-discipline.md" \
    "Read one reference file per call." "must say to read one reference file per call"
fi

# Checks 11 to 14 share a reading of the usage line. A mechanic whose --help
# check 5 reported has no line saved and is skipped here, so one fault is one
# report. `tail_of` drops the name; `usage_alts` splits what is left at the
# top-level ` | `, a ` | ` inside [...] or (...) belonging to its group.
tail_of() { local t=${2#"usage: $1"}; printf '%s' "${t# }"; }
usage_alts() {
  printf '%s\n' "$1" | awk '{
    d = 0; cur = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (c == "[" || c == "(") d++
      else if (c == "]" || c == ")") d--
      if (d == 0 && substr($0, i, 3) == " | ") { print cur; cur = ""; i += 2; continue }
      cur = cur c
    }
    print cur }'
}
# lead_slots <text>: the <slots> before the first token starting with [, ( or -.
lead_slots() {
  local t out=""
  set -f
  for t in $1; do
    case $t in '['*|'('*|-*) break ;; '<'*) out="$out $t" ;; esac
  done
  set +f
  printf '%s' "${out# }"
}
# call_slots <text>: the positionals of a valid call, one per line: literal
# words kept (a verb), an id as 1, <type> as fix, any other <slot> as x. A
# token ending in a comma ends the slots, so prose after a verb is not one.
call_slots() {
  local t lit
  set -f
  for t in $1; do
    case $t in '['*|'('*|-*|'"'*) break ;; esac
    case $t in
      '<issue>'|'<pr>'|'<n>'|'<issue|none>') echo 1 ;;
      '<type>') echo fix ;;
      '<'*) echo x ;;
      *) lit=${t%,}; echo "${lit%%|*}" ;;
    esac
    case $t in *,) break ;; esac
  done
  set +f
}
# flags_of <text>: the sorted, space-joined set of --flags in the text.
flags_of() { printf '%s\n' "$1" | grep -oE -e '--[a-z][a-z-]*' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
# required_flags <usage tail>: one line per flag the call must carry, the flags
# of a `( --a <x> | --b )` group joined by `|` (one of them), anything inside
# [...] left out.
required_flags() {
  printf '%s\n' "$1" | awk '
    function flags(str, sep,   r) {
      r = ""
      while (match(str, /--[a-z][a-z-]*/)) { r = r (r == "" ? "" : sep) substr(str, RSTART, RLENGTH); str = substr(str, RSTART + RLENGTH) }
      return r
    }
    { d = 0; g = 0; top = ""; grp = ""; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (c == "[") { d++; continue }
        if (c == "]") { d--; continue }
        if (d > 0) continue
        if (c == "(") { g = 1; grp = ""; continue }
        if (c == ")") { g = 0; print flags(grp, "|"); continue }
        if (g) grp = grp c; else top = top c
      }
      n = split(flags(top, " "), f, " ")
      for (i = 1; i <= n; i++) print f[i] }'
}

# flag_value <flag>: a value that passes the flag's own guard, for a call that
# must get past the flags and fail somewhere else.
flag_value() {
  case $1 in
    --body-file) printf '%s' "$work/body.md" ;; --title) printf 'fix: x' ;; --label) printf 'needs-triage' ;;
    --reviewer) printf 'copilot' ;; --section) printf 'Review' ;; --scratchpad) printf '%s' "$work" ;; *) printf 'x' ;;
  esac
}
# call_args <alt> [<flag>]: sets `args` to a valid call of the alternative, its
# positionals and every required flag with a valid value, leaving out the
# requirement <flag> belongs to. Check 12 gives <flag> its own bad value after
# these: with the others missing, a guard that admits the bad value is hidden
# behind the usage line the missing flag earns.
call_args() {
  local alt=$1 skip=${2:-} a r f
  args=()
  while IFS= read -r a; do [ -z "$a" ] || args+=("$a"); done <<EOP
$(call_slots "$alt")
EOP
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    if [ -n "$skip" ]; then case "|$r|" in *"|$skip|"*) continue ;; esac; fi
    f=${r%%|*}
    case $alt in
      *"$f <"*|*"$f \"<"*) args+=("$f" "$(flag_value "$f")") ;;
      *) args+=("$f") ;;
    esac
  done <<EOR
$(required_flags "$alt")
EOR
}

printf 'readable body\n' > "$work/body.md" || { echo "cannot create a temp file" >&2; exit 2; }

# 11. The header synopsis agrees with the usage line. The header is what a
# maintainer reads and the usage line is what a run reads, and they were typed
# apart: `open-pr` documented `<issue>` for a slot that also takes `none`, and
# `run-file` named `<where>` where the flags are. Compared as two sets: the
# --flags, over the synopsis block (the header lines from the first one opening
# with the mechanic's name to the next line that is exactly `#`) and the usage
# line, and the leading <slots>, over the block's first line and the usage line.
# A mechanic with no synopsis block is a stub with no header to compare.
for path in "$dir"/*.sh; do
  m=$(basename "$path" .sh)
  [ -f "$work/$m.usage" ] || continue
  block=$(awk -v m="$m" '$0 ~ "^#   " m "( |$)" { on = 1 } on && $0 == "#" { exit } on { print }' "$path")
  [ -n "$block" ] || continue
  usage=$(cat "$work/$m.usage"); utail=$(tail_of "$m" "$usage")
  first=$(printf '%s\n' "$block" | head -1); first=${first#"#   $m"}
  hf=$(flags_of "$block"); uf=$(flags_of "$utail")
  hs=$(lead_slots "$first"); us=$(lead_slots "$utail")
  diff=""
  [ "$hf" = "$uf" ] || diff="flags (header: ${hf:-none}; usage: ${uf:-none})"
  [ "$hs" = "$us" ] || diff="${diff:+$diff; }leading slots (header: ${hs:-none}; usage: ${us:-none})"
  [ -z "$diff" ] || { printf '%s: header synopsis and --help usage line disagree: %s\n' "$m" "$diff"; rc=1; }
done

# 12. Every flag that takes a value refuses a leading-dash one, with the usage
# line and exit 2. A guard that tests only for an empty value reads the next
# flag as the value: `open-pr --title --body-file b.md` took `--body-file` as
# the title. The flags are the usage line's `--flag <value>` pairs; the call
# gives the flag the positionals of the first alternative that names it, so a
# verb mechanic sees a verb it knows, and `--x` as its value.
for path in "$dir"/*.sh; do
  m=$(basename "$path" .sh)
  [ -f "$work/$m.usage" ] || continue
  apath=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
  usage=$(cat "$work/$m.usage"); utail=$(tail_of "$m" "$usage")
  # A variadic flag (`--carry <file>...`) ends its list at the next flag, so a
  # dash-led token after it is a flag, never its value.
  variadic=$(printf '%s\n' "$utail" | grep -oE -e '--[a-z][a-z-]* "?<[^ ]*>\.\.\.' | sed 's/ .*//')
  for f in $(printf '%s\n' "$utail" | grep -oE -e '--[a-z][a-z-]* "?<' | sed 's/ .*//' | sort -u); do
    case " $(echo $variadic) " in *" $f "*) continue ;; esac
    alt=$utail
    while IFS= read -r a; do
      case $a in *"$f <"*|*"$f \"<"*) alt=$a; break ;; esac
    done <<EOA
$(usage_alts "$utail")
EOA
    call_args "$alt" "$f"
    out=$(cd "$nogit" && bash "$apath" ${args[@]+"${args[@]}"} "$f" --x 2>/dev/null); st=$?
    if [ "$st" -ne 2 ] || ! printf '%s' "$out" | jq -se --arg u "$usage" 'length == 1 and (.[0] | type == "object" and .error == $u)' >/dev/null 2>&1; then
      printf '%s: %s took a leading-dash value; guard it with ship_flag_value so it answers the usage line and exit 2\n' "$m" "$f"
      rc=1
    fi
  done
done

# 13. A host failure prints exactly one JSON object. Each mechanic that loads a
# host adapter is run against the Host fake with every host function failing,
# from a throwaway checkout whose origin names GitHub, and what it prints on
# stdout has to be one object whatever its exit code: a run reads the answer
# with jq, and an exit path that prints nothing or two objects reads as a
# different failure than the one that happened. The call is a valid one (its
# positionals, and every required flag with a value that passes its guard), so
# the failure reached is the host's. `gh` and `az` stubs exit 127 and git may
# speak only `file:`, so nothing leaves the machine. A tree without the fake has
# nothing to drive.
fake=$(dirname "$0")/../tests/host-fake.sh
if [ -f "$fake" ]; then
  fake=$(cd "$(dirname "$fake")" && pwd)/host-fake.sh
  root=$(cd "$(dirname "$0")/.." && pwd)
  # The function list is the fake's own, so a host function added there is
  # failed here without this file learning of it.
  fns=$(sed -n '/^for _fn in/,/; do$/p' "$fake" | tr -s ' \\' '\n\n' | tr -d ';' | grep '^host_')
  [ -n "$fns" ] || { printf '%s: no host_* function on its `for _fn in` line; check 13 has nothing to fail\n' "$fake"; rc=1; }
  mkdir -p "$work/bin"
  for cli in gh az; do printf '#!/bin/sh\nexit 127\n' > "$work/bin/$cli"; chmod +x "$work/bin/$cli"; done
  for path in "$dir"/*.sh; do
    [ -n "$fns" ] || break
    m=$(basename "$path" .sh)
    [ -f "$work/$m.usage" ] || continue
    grep -q 'ship_load_host' "$path" || continue
    apath=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
    usage=$(cat "$work/$m.usage"); utail=$(tail_of "$m" "$usage")
    alt=$(usage_alts "$utail" | head -1)
    call_args "$alt"
    repo=$(mktemp -d "$work/repo.XXXXXX") && sf=$(mktemp -d "$work/fake.XXXXXX") || { echo "cannot create a temp directory" >&2; exit 2; }
    for fn in $fns; do : > "$sf/$fn.1.fail"; done
    mkdir -p "$repo/docs/agents" "$repo/.github"
    cp "$root/docs/agents/ship.md" "$repo/docs/agents/" || { printf '%s: check 13 setup failed: cannot copy docs/agents/ship.md\n' "$m"; rc=1; continue; }
    cp "$root/.github/pull_request_template.md" "$repo/.github/" || { printf '%s: check 13 setup failed: cannot copy .github/pull_request_template.md\n' "$m"; rc=1; continue; }
    ( cd "$repo" && git init -q . && git remote add origin https://github.com/o/r.git \
        && git -c user.name=gate -c user.email=gate@example.com -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q --allow-empty -m init ) >/dev/null 2>&1 \
      || { printf '%s: check 13 setup failed: cannot git init the throwaway checkout\n' "$m"; rc=1; continue; }
    out=$(cd "$repo" && PATH="$work/bin:$PATH" SHIP_HOST_ADAPTER=$fake SHIP_FAKE=$sf GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 \
      bash "$apath" ${args[@]+"${args[@]}"} 2>/dev/null </dev/null)
    if ! printf '%s' "$out" | jq -se 'length == 1 and (.[0] | type == "object")' >/dev/null 2>&1; then
      n="$(printf '%s' "$out" | jq -s length 2>/dev/null) JSON values" || n="unparseable output"
      call=$m; [ "${#args[@]}" -eq 0 ] || call="$m ${args[*]}"
      printf '%s: with every host_* failing in the Host fake, `%s` printed %s on stdout; want exactly one object\n' "$m" "$call" "$n"
      rc=1
    fi
  done
fi

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

exit $rc
