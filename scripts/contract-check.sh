#!/usr/bin/env bash
# The mechanics' malformed-invocation contract, enforced. Every mechanic reports
# a malformed invocation as {"error": "<usage>"} on stdout with exit 2; the ship
# profile's `## Public surface` names that as a contract, and a mechanic written
# with the pre-#62 `${N:?}` idiom reintroduces exit 1 with a bare shell
# diagnostic and no JSON. The `contract` gate in scripts/local-gate.sh is this.
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
# Check 5 is the --help contract: a run asks a mechanic what its flags are by
# running it, so the answer has to be the usage line, on stdout, exit 0.
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
# one JSON object carrying an `error` key and exits 2. The four listed here take
# no positional, so a bare invocation of one is a real run, not a malformed one.
takes_no_positional=" base-fresh select tooling list-prs "
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
# author rewords, never a silent pass. The setup-skills local gate is excluded:
# it is a template written into a consumer repo as that repo's own repo-local
# gate, behind its own Bash 4 version guard.
bash4='(^|[^[:alnum:]_])(mapfile|readarray)([^[:alnum:]_]|$)|(declare|local|typeset)([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*A|\$\{([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*])(\[[^]]*\])?(,|\^)'
raw=$(grep -rnE --include='*.sh' "$bash4" "$skills"); st=$?
[ "$st" -le 1 ] || { printf 'cannot search %s\n' "$skills" >&2; exit 2; }
# Both exclusions read the `path:line:content` fields rather than the whole
# line: a grep for either anywhere in it drops a real violation whose own
# content happens to carry `:12: #` or the template's path.
hits=$(printf '%s' "$raw" | awk -F: -v tmpl="$skills/setup-skills/local-gate.sh" '
  $1 == tmpl { next }
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

# 5. Every mechanic answers `--help` with its own usage line on stdout, exit 0
# and nothing on stderr. No mechanic is exempt, the four that take no positional
# included: a run reads a mechanic's flags by running it, and one that has none
# still answers with its name.
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
trap 'rm -f "$err"; rm -rf "$nogit"' EXIT
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
  case $out in
    "usage: $m"|"usage: $m "*) ;;
    *) printf '%s: --help did not print its own usage line on stdout\n' "$m"; rc=1; continue ;;
  esac
  # The usage line and nothing else: a case pattern matches across newlines, so
  # the prefix above accepts whatever a mechanic prints under it.
  if [ "$(printf '%s\n' "$out" | wc -l)" -ne 1 ]; then
    printf '%s: --help printed more than its usage line on stdout\n' "$m"
    rc=1
    continue
  fi
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

exit $rc
