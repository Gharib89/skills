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
# stdout: one line per violation, with the offending mechanic named
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
bash4='(^|[^[:alnum:]_])(mapfile|readarray)([^[:alnum:]_]|$)|(declare|local|typeset)[[:space:]]+-[A-Za-z]*A|\$\{([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*])(\[[^]]*\])?(,|\^)'
raw=$(grep -rnE --include='*.sh' "$bash4" "$skills"); st=$?
[ "$st" -le 1 ] || { printf 'cannot search %s\n' "$skills" >&2; exit 2; }
hits=$(printf '%s' "$raw" \
  | grep -vE ':[0-9]+:[[:space:]]*#' \
  | grep -vF "$skills/setup-skills/local-gate.sh:")
if [ -n "$hits" ]; then
  echo "Bash 4+ construct under $skills; everything a consumer installs targets Bash 3.2, where the missing builtin is a skipped line and a silent pass:"
  echo "$hits"
  rc=1
fi

exit $rc
