#!/usr/bin/env bash
# explainer-video's Node tests, `tests/explainer-video/*.test.mjs`, under
# `node --test`. Each drives the skill's scripts as a process against a temp
# tool cache, with the canned backend `fake-backend.mjs` selected through
# EXPLAINER_VIDEO_BACKEND, so none reaches the network or installs a thing.
#
#   tests/explainer-video.test.sh [--turn [--list] [<file>...]]
#
# `--turn` is the harness's turn rung, which has 60 s: it leaves out the files
# that run the render and gates pipeline once per case, `gates-*` and
# `render-*`, which together take longer than that. It also leaves out the
# three that run the real ffmpeg, `style-motion-real`, `motion-real` and
# `backend-concat`, so a turn never takes CPU from a timed render in another
# session. Given changed files,
# relative to the caller's directory as the turn rows pass them, it runs only
# the --turn files they reach. A changed test reaches itself. A changed .mjs or
# .js reaches every file under the skill or its tests (Markdown aside) whose
# text names its basename after a `/` or a quote: an import, a script a test
# runs, a page that loads it; those files' names reach further, to a fixed
# point. A file that is gone, is neither .mjs nor .js (package.json), or reaches
# no --turn file selects the whole --turn set rather than nothing; changed
# skipped tests alone select nothing here, the full rung running them.
# `--list` prints the selection instead of running it.
# The full rung and the local gate run `tests/run.sh`, which passes no flag and
# so runs every file.
#
# exit: 0 pass · 1 fail · 2 the skill's or its tests' files cannot be read
set -uo pipefail
caller=$(pwd -P)
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
root=$(pwd -P)
source tests/lib.sh

nl=$'\n'
quotes="\"'\`"
# <list> <line>: 0 when the newline-separated list holds the line.
holds() { case $nl$1$nl in *"$nl$2$nl"*) return 0 ;; esac; return 1; }
# <file>: the test files the file reaches, one per line; 2 on a grep error.
reach() {
  local names=${1##*/} seen=" ${1##*/} " found='' hits h b re
  while [ -n "$names" ]; do
    re=$(printf '%s\n' "$names" | sed '/^$/d; s/[]*^$+?(){}|\\.[]/\\&/g' | paste -sd'|' -)
    hits=$(grep -rlE --exclude='*.md' --exclude-dir=node_modules -- "[/$quotes]($re)" skills/explainer-video tests/explainer-video)
    [ $? -le 1 ] || return 2
    names=''
    while IFS= read -r h; do
      case $h in
        '') ;;
        *.test.mjs) found="$found$h$nl" ;;
        *) b=${h##*/}
           case $seen in *" $b "*) ;; *) seen="$seen$b " names="$names$b$nl" ;; esac ;;
      esac
    done <<EOF
$hits
EOF
  done
  printf '%s' "$found"
}

files=(tests/explainer-video/*.test.mjs)
list=''
if [ "${1:-}" = --turn ]; then
  shift
  [ "${1:-}" = --list ] && { list=1; shift; }
  kept=()
  for f in "${files[@]}"; do
    case ${f##*/} in
      gates-*.test.mjs | render-*.test.mjs | style-motion-real.test.mjs | motion-real.test.mjs | backend-concat.test.mjs) ;;
      *) kept+=("$f") ;;
    esac
  done
  files=("${kept[@]}")
  reached='' whole=''
  for f; do
    case $f in /*) ;; *) f=$caller/$f ;; esac
    # Through the directory's real path, so a `..` or a linked directory names
    # the file the trees hold; a directory that is gone took the file with it.
    d=$(cd -- "${f%/*}" 2>/dev/null && pwd -P) || { whole=1; break; }
    f=$d/${f##*/}
    f=${f#"$root"/}
    [ -f "$f" ] || { whole=1; break; }
    case $f in
      tests/explainer-video/*.test.mjs) reached="$reached$f$nl"; continue ;;
      skills/explainer-video/*.mjs | skills/explainer-video/*.js | tests/explainer-video/*.mjs) ;;
      *) whole=1; break ;;
    esac
    tests=$(reach "$f") || exit 2
    hit=''
    for k in "${files[@]}"; do holds "$tests" "$k" && { hit=1; break; }; done
    [ -n "$hit" ] || { whole=1; break; }
    reached="$reached$tests$nl"
  done
  if [ "$#" -gt 0 ] && [ -z "$whole" ]; then
    kept=()
    for f in "${files[@]}"; do holds "$reached" "$f" && kept+=("$f"); done
    # Only skipped tests changed: nothing of theirs runs on this rung.
    [ "${#kept[@]}" -gt 0 ] || exit 0
    files=("${kept[@]}")
  fi
fi
if [ -n "$list" ]; then printf '%s\n' "${files[@]}"; exit 0; fi

command -v node >/dev/null || { echo "FAIL explainer-video: node not on PATH" >&2; exit 1; }

out=$(node --test --test-timeout=180000 "${files[@]}" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || printf '%s\n' "$out" | grep -E '^not ok|^# (pass|fail)|AssertionError|Error|expected|actual' | head -40 >&2
check_rc "node --test tests/explainer-video" 0 "$rc"

finish
