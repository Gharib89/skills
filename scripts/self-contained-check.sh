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
# and a relative link leaving the skill, written inline or as a reference
# definition, including one whose destination is on the next line or whose
# label escapes a `]`. A blockquote's `>` markers are stripped first, so its
# content is read as any other, and a fence opened in one ends with it. A
# fence opens and closes as CommonMark has it: a closer is its own character
# at its own length or longer with nothing after it, and a backtick run
# followed by a backtick is inline code, so a nested example block cannot
# switch the prose checks off. `CHANGELOG.md` carries provenance and is exempt.
# `scripts/check.sh full` runs this as its `self-contained` row, which
# scripts/local-gate.sh reports under the same name.
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
fence='^[[:space:]]*(`{3,}|~{3,})(.*)$'
label='^ {0,3}\[((\\.|[^]\\^])(\\.|[^]\\])*)?\]:[[:space:]]*'
refdef="$label"'(<[^>]*>|[^[:space:]<]+)'
refopen="$label"'$'
destline='^[[:space:]]*(<[^>]*>|[^[:space:]<]+)'
quote='^ {0,3}> ?(.*)$'

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
  n=0 fence_char='' fence_len=0 fence_depth=0 pending=''
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if printf '%s\n' "$line" | grep -oiE "$url" | grep -qviE "$destination"; then
      printf '%s:%s: links source-repo material by URL\n' "$f" "$n"; rc=1
    fi
    prev=$pending pending='' body=$line depth=0
    while [[ $body =~ $quote ]]; do body=${BASH_REMATCH[1]}; depth=$((depth + 1)); done
    [ "$depth" -lt "$fence_depth" ] && fence_char='' fence_depth=0
    if [[ $body =~ $fence ]]; then
      run=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
      if [ -z "$fence_char" ]; then
        # a backtick run with a backtick after it is inline code, not a fence
        if [ "${run:0:1}" != '`' ] || [[ $rest != *'`'* ]]; then
          fence_char=${run:0:1} fence_len=${#run} fence_depth=$depth; continue
        fi
      elif [ "${run:0:1}" = "$fence_char" ] && [ "${#run}" -ge "$fence_len" ] \
        && [[ $rest != *[![:space:]]* ]]; then
        fence_char='' fence_depth=0; continue
      fi
    fi
    [ -z "$fence_char" ] || continue
    prose=$(printf '%s\n' "$body" | sed 's/`[^`]*`//g')
    if printf '%s\n' "$prose" | grep -qiE "$number"; then
      printf '%s:%s: cites an issue or PR number\n' "$f" "$n"; rc=1
    fi
    while IFS= read -r target; do
      case $target in *://*|mailto:*|/*|'') continue ;; esac
      resolved=$(normalize "$dir/${target%%#*}")
      case $resolved/ in "$skill"/*) ;; *)
        printf '%s:%s: links outside %s/: %s\n' "$f" "$n" "$skill" "$target"; rc=1 ;;
      esac
    done < <(
      printf '%s\n' "$prose" | grep -oE '\]\([^)[:space:]]+' | sed 's/^](//'
      t=''
      if [[ $prose =~ $refdef ]]; then t=${BASH_REMATCH[4]}
      elif [ -n "$prev" ] && [[ $prose =~ $destline ]]; then t=${BASH_REMATCH[1]}; fi
      t=${t#<}; [ -z "$t" ] || printf '%s\n' "${t%>}"
    )
    [[ $prose =~ $refopen ]] && pending=1
  done < "$root/$f"
done < <(git -C "$root" ls-files 'skills/*.md')
exit $rc
