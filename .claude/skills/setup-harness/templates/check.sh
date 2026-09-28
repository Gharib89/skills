#!/usr/bin/env bash
# scripts/check.sh: this repo's check entry point, written by setup-harness.
#
#   scripts/check.sh edit <file>...   lint and format the files, fix mode
#   scripts/check.sh turn [<file>...] typecheck and affected tests; default
#                                     file set: every uncommitted change
#   scripts/check.sh full             the whole repo
#
# stdout: one JSON line {"rung","verdict","checks":{<name>:<status>}}, status
#         pass | fail | unavailable | skipped | over-budget
# stderr: each failing check's last 40 lines
# exit:   0 pass · 1 fail · 2 unavailable or tooling · 3 over budget
#
# CHECK_DEADLINE=<epoch s> stops the run at that time: the running check is
# over-budget, the rest skipped, exit 3. Without it, exit 3 never occurs.
#
# Bash 3.2 and no jq, because hooks run this on every edit on macOS too. Edit
# the configuration block freely: a setup-harness re-run compares this file by
# what it says and keeps what you added.
set -uo pipefail
# File lists and globs here are data, so no pathname expansion; the commands
# the configuration names get it back in their own subshell.
set -f

# >>> setup-harness configuration
# Files the edit rung covers, as shell globs on the file name; any other file
# is `skipped`.
EDIT_GLOBS=''
# The runner on a file list ({files}), and on every file for `full`.
EDIT_RUN=''
FULL_RUN=''
# The turn table, one row per member:
#   <path prefix>|<member>|<globs>|<typecheck>|<tests>|<affected tests>
# A changed file matching a row's globs belongs to the row with the longest
# prefix it sits under (an empty prefix is the repo root). Commands run in the
# member's directory; <affected tests> takes {files}, relative to it, and an
# empty one runs <tests>. An empty command is no check.
TURN_ROWS=''
# Extra checks on `full` only, one per line: <name>|<command>, from the root.
FULL_ROWS=''
# <<< setup-harness configuration
: "${EDIT_GLOBS=}" "${EDIT_RUN=}" "${FULL_RUN=}" "${TURN_ROWS=}" "${FULL_ROWS=}"

rung=${1:-}
case $rung in
  edit | turn | full) shift ;;
  *) printf 'usage: check.sh edit <file>... | turn [<file>...] | full\n' >&2; exit 2 ;;
esac
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "check.sh: not in a git repo" >&2; exit 2; }
cd "$root" || exit 2
nl='
'
deadline=${CHECK_DEADLINE:-}
names='' statuses='' expired=''
record() { names="$names$1$nl" statuses="$statuses$2$nl"; }

# <name> <dir> <command> [<tries>]: run one check, recording its status; a
# failing check's tail goes to stderr. Two tries for a runner in fix mode: the
# first run's fixes fail it, and only what they leave fails the second. Past
# the deadline a check is skipped unrun; one still running at it is killed,
# with its whole process group, and is over-budget.
check() {
  local name=$1 dir=$2 cmd=$3 tries=${4:-1} log rc pid dog now
  if [ -n "$expired" ]; then record "$name" skipped; return; fi
  log=$(mktemp) || exit 2
  while :; do
    if [ -n "$deadline" ]; then
      now=$(date +%s)
      if [ "$now" -ge "$deadline" ]; then expired=1; rc=124; break; fi
      set -m
      (cd "$dir" && set +f && eval "$cmd") > "$log" 2>&1 &
      pid=$!
      (sleep $((deadline - now)); kill -TERM -- "-$pid" 2>/dev/null) > /dev/null 2>&1 &
      dog=$!
      set +m
      wait "$pid"; rc=$?
      if kill -0 "$dog" 2>/dev/null; then kill -TERM -- "-$dog" 2>/dev/null; else expired=1; rc=124; break; fi
    else
      (cd "$dir" && set +f && eval "$cmd") > "$log" 2>&1
      rc=$?
    fi
    tries=$((tries - 1))
    [ "$rc" -ne 0 ] && [ "$rc" -ne 127 ] && [ "$tries" -gt 0 ] || break
  done
  case $rc in
    0) record "$name" pass ;;
    124) record "$name" over-budget ;;
    127) record "$name" unavailable; { printf -- '--- %s: unavailable ---\n' "$name"; tail -n 40 "$log"; } >&2 ;;
    *) record "$name" fail; { printf -- '--- %s ---\n' "$name"; tail -n 40 "$log"; } >&2 ;;
  esac
  rm -f "$log"
}

# The files, shell-quoted and space-joined, for a {files} placeholder.
quoted() { local f q=''; for f; do q="$q $(printf '%q' "$f")"; done; printf '%s' "${q# }"; }

matches() { # <file> <globs>: 0 when one of the globs matches the file name
  local g
  for g in $2; do
    # shellcheck disable=SC2254 # the globs are patterns by design
    case ${1##*/} in $g) return 0 ;; esac
  done
  return 1
}

rung_edit() {
  local f files=''
  for f; do
    case $f in "$root"/*) f=${f#"$root"/} ;; esac
    [ -f "$f" ] && matches "$f" "$EDIT_GLOBS" && files="$files$f$nl"
  done
  if [ -z "$files" ] || [ -z "$EDIT_RUN" ]; then record runner skipped; return; fi
  local IFS=$nl
  # shellcheck disable=SC2086 # the list splits on newlines only
  set -- $files
  unset IFS
  check runner . "${EDIT_RUN//\{files\}/$(quoted "$@")}" 2
}

# <file>: the TURN_ROWS row owning the file, else nothing. Prints `new-root`
# for a file some row's globs match under no row's prefix.
owner() {
  local row prefix member globs best='' blen=-1 kind=''
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    prefix=${row%%|*} member=${row#*|}; globs=${member#*|}; globs=${globs%%|*}
    matches "$1" "$globs" || continue
    kind=1
    case $1 in "$prefix"*) ;; *) continue ;; esac
    [ "${#prefix}" -gt "$blen" ] && best=$row blen=${#prefix}
  done <<EOF
$TURN_ROWS
EOF
  if [ -n "$best" ]; then printf '%s' "$best"; elif [ -n "$kind" ]; then printf new-root; fi
}

# <row> [<files, relative to the root>]: the row's typecheck and tests.
# `full` passes no files and gets the member's whole suite.
run_row() {
  local row=$1 prefix member typecheck tests affected dir f rel=''
  shift
  IFS='|' read -r prefix member _ typecheck tests affected <<EOF
$row
EOF
  dir=${prefix:-.}
  [ -n "$typecheck" ] && check "typecheck:$member" "$dir" "$typecheck"
  if [ "$#" -gt 0 ] && [ -n "$affected" ]; then
    for f; do rel="$rel${f#"$prefix"}$nl"; done
    local IFS=$nl
    # shellcheck disable=SC2086 # the list splits on newlines only
    set -- $rel
    unset IFS
    check "tests:$member" "$dir" "${affected//\{files\}/$(quoted "$@")}"
  elif [ -n "$tests" ]; then
    check "tests:$member" "$dir" "$tests"
  fi
}

rung_turn() {
  local f o rows='' pairs='' row files pair tab='	' new=''
  if [ "$#" -eq 0 ]; then
    # Every uncommitted change, untracked files included; a rename line
    # carries its new path last.
    local IFS=$nl
    # shellcheck disable=SC2046 # one path per line
    set -- $(git status --porcelain --untracked-files=all | sed 's/^...//; s/.* -> //')
    unset IFS
  fi
  for f; do
    case $f in "$root"/*) f=${f#"$root"/} ;; esac
    o=$(owner "$f")
    case $o in
      '') ;;
      new-root) new="$new ${f%/*}" ;;
      *) case $nl$rows in *"$nl$o$nl"*) ;; *) rows="$rows$o$nl" ;; esac
         pairs="$pairs$o$tab$f$nl" ;;
    esac
  done
  if [ -n "$new" ]; then
    record new-root unavailable
    printf -- '--- new-root: unavailable ---\nnew root %s: re-run setup-harness\n' "${new# }" >&2
  fi
  if [ -z "$rows" ] && [ -z "$new" ]; then record turn skipped; return; fi
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    files=''
    while IFS= read -r pair; do
      [ "${pair%%"$tab"*}" = "$row" ] && files="$files${pair#*"$tab"}$nl"
    done <<EOF
$pairs
EOF
    local IFS=$nl
    # shellcheck disable=SC2086 # the list splits on newlines only
    set -- $files
    unset IFS
    run_row "$row" "$@"
  done <<EOF
$rows
EOF
}

rung_full() {
  local row name
  [ -n "$FULL_RUN" ] && check runner . "$FULL_RUN"
  while IFS= read -r row; do
    [ -n "$row" ] && run_row "$row"
  done <<EOF
$TURN_ROWS
EOF
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    name=${row%%|*}
    check "$name" . "${row#*|}"
  done <<EOF
$FULL_ROWS
EOF
  [ -n "$names" ] || record full skipped
}

"rung_$rung" "$@"

# One JSON line. A real failure outranks every other outcome, so it still
# reaches the caller when the deadline also hit.
json='' seen='' i=0
while IFS= read -r n; do
  [ -n "$n" ] || continue
  i=$((i + 1))
  s=$(printf '%s' "$statuses" | sed -n "${i}p")
  n=${n//\\/\\\\}; n=${n//\"/\\\"}
  json="$json,\"$n\":\"$s\"" seen="$seen $s"
done <<EOF
$names
EOF
case $seen in
  *fail*) verdict=fail code=1 ;;
  *over-budget*) verdict=over-budget code=3 ;;
  *unavailable*) verdict=unavailable code=2 ;;
  *pass*) verdict=pass code=0 ;;
  *) verdict=skipped code=0 ;;
esac
printf '{"rung":"%s","verdict":"%s","checks":{%s}}\n' "$rung" "$verdict" "${json#,}"
exit $code
