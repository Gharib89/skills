#!/usr/bin/env bash
# A skill's prose pointing at material that does not install with it. A derived
# copy carries `skills/<name>/` and nothing above it, so a relative link out of
# that directory dangles, and a URL to this repo's files or tracker is material a
# running agent does not fetch and that drifts from the pinned copy. setup-harness
# 0.5.0 shipped its vocabulary as a `CONTEXT.md` URL and the `derived-copies` gate,
# comparing bytes, could not see it. The coding standards' self-contained bullet
# is the rule; this is the part of it a grep can hold: source-repo URLs other than
# the bare issue tracker (a destination), `PR #N` or `issue #N` outside a code
# span, and relative links leaving the skill. `CHANGELOG.md` carries provenance
# and is exempt. The `self-contained` gate in scripts/local-gate.sh runs this.
#
#   scripts/self-contained-check.sh [<root>]
#
# stdout: one `<path>:<line>: <reason>` per finding, nothing when clean
# exit: 0 clean · 1 a finding · 2 tooling
set -uo pipefail
root=${1:-.}
[ -d "$root" ] || { printf 'not a directory: %s\n' "$root" >&2; exit 2; }
toplevel=$(git -C "$root" rev-parse --show-toplevel) || exit 2
[ "$toplevel" = "$(cd "$root" && pwd -P)" ] \
  || { printf 'not the top of a checkout: %s\n' "$root" >&2; exit 2; }

url='(github\.com/Gharib89/skills/(blob|tree|raw|pull|commit|issues/[0-9])|raw\.githubusercontent\.com/Gharib89/skills)'
number='(^|[^[:alnum:]])(PR|issue) #[0-9]+'

# normalize <path>: `a/b/../c` -> `a/c`, `./` dropped; a `..` above the root is
# kept, so the prefix test below fails on it.
normalize() {
  local out=() part
  local IFS=/
  for part in $1; do
    case $part in
      ''|.) ;;
      ..) if [ "${#out[@]}" -gt 0 ] && [ "${out[-1]}" != .. ]; then unset 'out[-1]'; else out+=(..); fi ;;
      *) out+=("$part") ;;
    esac
  done
  printf '%s' "${out[*]}"
}

rc=0
while IFS= read -r f; do
  case $f in */CHANGELOG.md) continue ;; esac
  skill=${f#skills/}; skill=skills/${skill%%/*}
  dir=${f%/*}
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if printf '%s\n' "$line" | grep -qE "$url"; then
      printf '%s:%s: links source-repo material by URL\n' "$f" "$n"; rc=1
    fi
    if printf '%s\n' "$line" | sed 's/`[^`]*`//g' | grep -qE "$number"; then
      printf '%s:%s: cites an issue or PR number\n' "$f" "$n"; rc=1
    fi
    while IFS= read -r target; do
      case $target in *://*|mailto:*|/*|'') continue ;; esac
      resolved=$(normalize "$dir/${target%%#*}")
      case $resolved/ in "$skill"/*) ;; *)
        printf '%s:%s: links outside %s/: %s\n' "$f" "$n" "$skill" "$target"; rc=1 ;;
      esac
    done < <(printf '%s\n' "$line" | grep -oE '\]\([^)[:space:]]+' | sed 's/^](//')
  done < "$root/$f"
done < <(git -C "$root" ls-files 'skills/*.md')
exit $rc
