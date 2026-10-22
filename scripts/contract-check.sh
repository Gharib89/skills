#!/usr/bin/env bash
# The mechanics' malformed-invocation contract, enforced. Every mechanic reports
# a malformed invocation as {"error": "<usage>"} on stdout with exit 2; the ship
# profile's `## Public surface` names that as a contract, and a mechanic written
# with the pre-#62 `${N:?}` idiom reintroduces exit 1 with a bare shell
# diagnostic and no JSON. `scripts/check.sh full` runs this as its `contract`
# row, which scripts/local-gate.sh reports under the same name.
#
#   scripts/contract-check.sh [<scripts-dir> [<skills-dir> [<extra-dir>...]]]
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
# Check 10 is retired: the two sentences of ship's prose it pinned are defaults
# now, with no reader to guard (ADR 0011).
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
# Check 16 greps the same files, and every shell file under each <extra-dir>,
# for a pipe into `grep -q` under pipefail, which fails open when the writer
# dies of SIGPIPE. The repo's own gate rows pass `scripts`, `tests` and
# `.claude/hooks`, since a gate script there fails open the same way.
#
# stdout: one line per violation, with the offending mechanic or file named
# exit: 0 the contract holds · 1 a violation · 2 tooling
set -uo pipefail
dir=${1:-skills/ship/scripts}
skills=${2:-skills}
extra=("${@:3}")
[ -d "$dir" ] || { printf 'not a directory: %s\n' "$dir" >&2; exit 2; }
[ -d "$skills" ] || { printf 'not a directory: %s\n' "$skills" >&2; exit 2; }
for d in ${extra[@]+"${extra[@]}"}; do [ -d "$d" ] || { printf 'not a directory: %s\n' "$d" >&2; exit 2; }; done
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
# one JSON object carrying an `error` key and exits 2. The eight listed here take
# no positional, so a bare invocation of one is a real run, not a malformed one.
takes_no_positional=" base-fresh select tooling list-prs prepare dropped-lines source-lock window "
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

# Checks 7 to 16 live beside this file, in the order they report. They are
# sourced, so they share `rc`, `work`, `dir`, `skills` and the rest.
here=$(dirname "${BASH_SOURCE[0]}")/contract-check.d
for part in harness usage shell; do
  # shellcheck source=/dev/null
  source "$here/$part.sh"
done

exit $rc
