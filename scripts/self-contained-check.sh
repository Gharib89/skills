#!/usr/bin/env bash
# A skill's prose pointing at material that does not install with it. A derived
# copy carries `skills/<name>/` and nothing above it, so a relative link out of
# that directory dangles, and a URL to this repo's files or tracker is material a
# running agent does not fetch and that drifts from the pinned copy. setup-harness
# 0.5.0 shipped its vocabulary as a `CONTEXT.md` URL and the `derived-copies` gate,
# comparing bytes, could not see it. The coding standards' self-contained bullet
# is the rule; this is the part of it a grep can hold: any source-repo URL but
# the repo root and its issue tracker (destinations), in any case, since GitHub
# resolves owner and repo case-insensitively; and outside a code span or a
# fenced block, where either is an example, `PR #N` or `issue #N` in any case
# and a relative link leaving the skill. `CHANGELOG.md` carries provenance and is exempt. The `self-contained`
# gate in scripts/local-gate.sh runs this.
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

url='(github\.com|raw\.githubusercontent\.com)/gharib89/skills(/[^[:space:])>`"]*)?'
destination='^github\.com/gharib89/skills(/|/issues/?|/issues/new[^/]*)?$'
number='(^|[^[:alnum:]])(PR|issue) #[0-9]+'
fence='^[[:space:]]*(```|~~~)'

# normalize <path>: `a/b/../c` -> `a/c`, `./` dropped; a `..` above the root is
# kept, so the prefix test below fails on it. Split by `read`, not an unquoted
# expansion, so a `*` in a target stays a segment rather than globbing, and the
# last index is counted rather than subscripted `-1`, which is Bash 4.3.
normalize() {
  local parts=() out=() part n=0
  IFS=/ read -r -a parts <<< "$1"
  for part in ${parts[@]+"${parts[@]}"}; do
    case $part in
      ''|.) ;;
      ..) if [ "$n" -gt 0 ] && [ "${out[$((n - 1))]}" != .. ]; then n=$((n - 1)); unset "out[$n]"; else out[n]=..; n=$((n + 1)); fi ;;
      *) out[n]=$part; n=$((n + 1)) ;;
    esac
  done
  local IFS=/
  printf '%s' "${out[*]+${out[*]}}"
}

rc=0
while IFS= read -r f; do
  case $f in */CHANGELOG.md) continue ;; esac
  skill=${f#skills/}; skill=skills/${skill%%/*}
  dir=${f%/*}
  n=0 fenced=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if printf '%s\n' "$line" | grep -oiE "$url" | grep -qviE "$destination"; then
      printf '%s:%s: links source-repo material by URL\n' "$f" "$n"; rc=1
    fi
    if [[ $line =~ $fence ]]; then fenced=$((1 - fenced)); continue; fi
    [ "$fenced" -eq 0 ] || continue
    prose=$(printf '%s\n' "$line" | sed 's/`[^`]*`//g')
    if printf '%s\n' "$prose" | grep -qiE "$number"; then
      printf '%s:%s: cites an issue or PR number\n' "$f" "$n"; rc=1
    fi
    while IFS= read -r target; do
      case $target in *://*|mailto:*|/*|'') continue ;; esac
      resolved=$(normalize "$dir/${target%%#*}")
      case $resolved/ in "$skill"/*) ;; *)
        printf '%s:%s: links outside %s/: %s\n' "$f" "$n" "$skill" "$target"; rc=1 ;;
      esac
    done < <(printf '%s\n' "$prose" | grep -oE '\]\([^)[:space:]]+' | sed 's/^](//')
  done < "$root/$f"
done < <(git -C "$root" ls-files 'skills/*.md')
exit $rc
