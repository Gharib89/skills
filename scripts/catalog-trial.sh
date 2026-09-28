#!/usr/bin/env bash
# The entry trial for setup-harness's catalog: proves an entry's install and
# run lines against real tools. Per `###` tool: pick the version by the
# catalog's version rule (packages only), install by `Route:`, run `Run:` on a
# copy of tests/fixtures/catalog/<entry>/clean/, which must pass without
# changing a file, then lay bad/<tool>/ over that copy and run it on the
# planted files, which must fail or change one. A tool marked `Unavailable:`
# is reported and not tried.
#
#   scripts/catalog-trial.sh <entry>|all
#
# Installs are real and global where the route is, so this runs in a cloud
# session (`claude --cloud`), never on a dev machine or in the local gate; it
# is required before an entry merges and on any later PR touching one.
#
# stdout: one `<entry> <tool>: pass | fail (<why>) | unavailable (<why>)` line per tool
# exit: 0 every tried tool passed · 1 a tool failed · 2 usage
set -uo pipefail
shopt -u patsub_replacement 2>/dev/null || :
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) || exit 2
catalog=$root/skills/setup-harness/catalog
seeds=$root/tests/fixtures/catalog
usage="usage: catalog-trial.sh <entry>|all"

case ${1:-} in
  -h | --help) echo "$usage"; exit 0 ;;
  '') echo "$usage" >&2; exit 2 ;;
  all) entries=$(cd "$catalog" && ls ./*.md | sed 's|^\./||; s|\.md$||' | grep -vx README) ;;
  *) [ -f "$catalog/$1.md" ] || { echo "no catalog entry $1" >&2; exit 2; }; entries=$1 ;;
esac

# The first backticked command on a line.
cmd() { printf '%s' "$1" | sed -n 's/^[^`]*`\([^`]*\)`.*/\1/p'; }
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//'; }
# A tree's contents as one string, to tell whether a run changed a file.
snapshot() { (cd "$1" && find . -type f ! -path './node_modules/*' ! -path './.venv/*' -exec cksum {} + | sort); }
# The files in a directory whose names carry one of the entry's extensions,
# shell-quoted for {files}.
files_in() {
  local f q=''
  while IFS= read -r f; do
    for e in $exts; do
      case $f in *"$e") q="$q $(printf '%q' "${f#./}")"; break ;; esac
    done
  done <<EOF
$(cd "$1" && find . -type f ! -path './node_modules/*' ! -path './.venv/*' | sort)
EOF
  printf '%s' "${q# }"
}

# <entry> <tool> <pin> <route> <run> <unavailable>
trial() {
  local entry=$1 tool=$2 pin=$3 route=$4 run=$5 unavail=$6 s version='' before files
  s=$(slug "$tool")
  if [ -n "$unavail" ]; then echo "$entry $s: unavailable ($unavail)"; return 0; fi
  case $pin in
    package\ *)
      set -- $pin
      version=$("$root/skills/setup-harness/scripts/pick-version.sh" "$2" "$3") \
        || { echo "$entry $s: fail (no version of $3 on $2)"; return 1; } ;;
  esac
  [ -d "$seeds/$entry/bad/$s" ] || { echo "$entry $s: fail (no bad/$s)"; return 1; }
  work=$(mktemp -d) || exit 2
  cp -R "$seeds/$entry/clean/." "$work/"
  (cd "$work" && bash -c "${route//\{version\}/$version}") >&2 \
    || { echo "$entry $s: fail (install)"; rm -rf "$work"; return 1; }
  files=$(files_in "$work")
  before=$(snapshot "$work")
  run=${run//\{member\}/.}
  if ! (cd "$work" && bash -c "${run//\{files\}/$files}") >&2 || [ "$(snapshot "$work")" != "$before" ]; then
    echo "$entry $s: fail (failed on clean)"; rm -rf "$work"; return 1
  fi
  cp -R "$seeds/$entry/bad/$s/." "$work/"
  files=$(files_in "$seeds/$entry/bad/$s")
  before=$(snapshot "$work")
  if (cd "$work" && bash -c "${run//\{files\}/$files}") >&2 && [ "$(snapshot "$work")" = "$before" ]; then
    echo "$entry $s: fail (passed on bad/$s)"; rm -rf "$work"; return 1
  fi
  echo "$entry $s: pass"
  rm -rf "$work"
}

# The trial tree in use, removed on any exit.
work=''
trap 'rm -rf "$work"' EXIT

rc=0
for entry in $entries; do
  exts=$(sed -n 's/^Extensions: //p' "$catalog/$entry.md" | head -n 1)
  tool='' pin='' route='' run='' unavail=''
  while IFS= read -r line; do
    case $line in
      '### '* | '## '* | __END__)
        [ -n "$tool" ] && { trial "$entry" "$tool" "$pin" "$route" "$run" "$unavail" < /dev/null || rc=1; }
        tool='' pin='' route='' run='' unavail=''
        case $line in '### '*) tool=${line#\#\#\# } ;; esac ;;
      'Pin: '*) pin=${line#Pin: } ;;
      'Route: '*) route=$(cmd "$line") ;;
      'Run: '*) run=$(cmd "$line") ;;
      'Unavailable: '*) unavail=${line#Unavailable: } ;;
    esac
  done <<EOF
$(cat "$catalog/$entry.md")
__END__
EOF
done
exit $rc
