#!/usr/bin/env bash
# The entry trial for setup-harness's catalog: proves an entry's install and run
# lines against real tools. Per `###` tool: pick the version by the install
# check's version choice (packages only), install by `Route:`, run `Run:` on a
# copy of tests/fixtures/catalog/<entry>/clean/, which must pass without
# changing a seed file, then lay bad/<tool>/ over that copy and run it on the
# planted files, which must fail or change one. A tool marked `Unavailable:` or
# `Local-only:` is reported and not tried, the trial running in a cloud
# session. <tool> is the `###` heading, lower-cased, with each run of other
# characters turned into `-`. {files} is every seed file the entry claims,
# by `Extensions:`, `Names:` (a basename at any depth) or `Paths:` (a glob
# on the seed-relative path); a tool with its own `Files:` gets only the
# files carrying those extensions instead. {version} is the picked version,
# {member} is `.` and {package} is `seed`, the package name every stack
# seed carries. The clean copy is a git repo whose one commit is tagged
# v0.1.0, the baseline a public-API tool diffs against (griffe). `Run:` runs
# with the tree's node_modules/.bin ahead of PATH, as a stack's exec command
# would, so a Route: installing into the tree (`npm install --no-save`) is the
# copy tried.
#
#   scripts/catalog-trial.sh <entry>|all
#
# Installs are real and global where the route is, so this runs in a cloud
# session (`claude --cloud`), never on a dev machine or in the local gate; it
# is required before an entry merges and on any later PR touching one.
#
# stdout: one line per tool, `<entry> <tool>: pass | fail (<why>) |
#   unavailable (<why>) | local-only (<why>)`
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
# <tree> <seed>...: the seed's own files as they stand in the tree. A
# formatter's rewrite changes one; a tool's cache (.ruff_cache, __pycache__)
# is none of them, so it is no change.
snapshot() {
  local w=$1 f s; shift
  for s; do (cd "$s" && find . -type f); done | sort -u | while IFS= read -r f; do
    (cd "$w" && cksum "$f" 2>/dev/null) || echo "gone $f"
  done
}
# <dir> <extensions> <names> <paths>: the files in a directory the entry
# claims, shell-quoted for {files}. Always run in a command substitution, so
# the `set -f` keeping a Paths: glob from matching the cwd stays in it.
files_in() {
  local f p q=''
  set -f
  while IFS= read -r f; do
    f=${f#./}
    for p in $2; do case $f in *"$p") q="$q $(printf '%q' "$f")"; continue 2 ;; esac; done
    for p in $3; do case ${f##*/} in "$p") q="$q $(printf '%q' "$f")"; continue 2 ;; esac; done
    # A Paths: `*` stays within one directory: the path and glob have as many `/`.
    # shellcheck disable=SC2254 # a Paths: entry is a glob, matched as one
    for p in $4; do case $f in $p) [ "${f//[!\/]/}" = "${p//[!\/]/}" ] && { q="$q $(printf '%q' "$f")"; continue 2; } ;; esac; done
  done <<EOF
$(cd "$1" && find . -type f ! -path './.git/*' ! -path './node_modules/*' ! -path './.venv/*' | sort)
EOF
  printf '%s' "${q# }"
}

# <entry> <label>: the entry's signal line, empty for `None.`.
signal() { sed -n "s/^$2: //p" "$catalog/$1.md" | head -n 1 | sed 's/^None\.$//'; }

# git for the clean copy's baseline, deaf to the host's hooks, signing and identity.
g() { git -c core.hooksPath=/dev/null -c commit.gpgSign=false -c tag.gpgSign=false -c user.name=trial -c user.email=trial@example.invalid "$@"; }

# <entry> <tool> <pin> <route> <run> <skip> <only>: a non-empty <skip> is the
# verdict of a tool that is not tried; a non-empty <only> is its Files:.
trial() {
  local entry=$1 tool=$2 pin=$3 route=$4 run=$5 skip=$6 only=$7 s version='' before files
  local e=$exts n=$names p=$paths
  [ -n "$only" ] && e=$only n='' p=''
  s=$(slug "$tool")
  if [ -n "$skip" ]; then echo "$entry $s: $skip"; return 0; fi
  case $pin in
    package\ *)
      set -- $pin
      shift # past `package`: a maven pin may name its repository before the name
      version=$("$root/skills/setup-harness/scripts/pick-version.sh" "$@")
      case $? in
        0) ;;
        2) echo "$entry $s: fail ($1 did not answer for ${pin##* })"; return 1 ;;
        *) echo "$entry $s: fail (no version of ${pin##* } on $1)"; return 1 ;;
      esac ;;
  esac
  [ -d "$seeds/$entry/bad/$s" ] || { echo "$entry $s: fail (no bad/$s)"; return 1; }
  work=$(mktemp -d) || exit 2
  cp -R "$seeds/$entry/clean/." "$work/"
  (cd "$work" && g init -q && g add -A && g commit -qm seed && g tag v0.1.0) >&2 \
    || { echo "$entry $s: fail (git baseline)"; rm -rf "$work"; return 1; }
  (cd "$work" && bash -c "${route//\{version\}/$version}") >&2 \
    || { echo "$entry $s: fail (install)"; rm -rf "$work"; return 1; }
  files=$(files_in "$work" "$e" "$n" "$p")
  before=$(snapshot "$work" "$seeds/$entry/clean")
  run=${run//\{member\}/.}
  run=${run//\{package\}/seed}
  run=${run//\{version\}/$version}
  if ! (cd "$work" && PATH=$work/node_modules/.bin:$PATH bash -c "${run//\{files\}/$files}") >&2 || [ "$(snapshot "$work" "$seeds/$entry/clean")" != "$before" ]; then
    echo "$entry $s: fail (failed on clean)"; rm -rf "$work"; return 1
  fi
  cp -R "$seeds/$entry/bad/$s/." "$work/"
  files=$(files_in "$seeds/$entry/bad/$s" "$e" "$n" "$p")
  before=$(snapshot "$work" "$seeds/$entry/clean" "$seeds/$entry/bad/$s")
  if (cd "$work" && PATH=$work/node_modules/.bin:$PATH bash -c "${run//\{files\}/$files}") >&2 && [ "$(snapshot "$work" "$seeds/$entry/clean" "$seeds/$entry/bad/$s")" = "$before" ]; then
    echo "$entry $s: fail (passed on bad/$s)"; rm -rf "$work"; return 1
  fi
  echo "$entry $s: pass"
  rm -rf "$work"
}

# A bad seed can match its clean file's size and land in the same second, which
# Python's bytecode check (mtime in seconds plus size) cannot tell apart, so a
# cached .pyc would run the clean code on the bad run.
export PYTHONDONTWRITEBYTECODE=1

# The trial tree in use, removed on any exit.
work=''
trap 'rm -rf "$work"' EXIT

rc=0
for entry in $entries; do
  exts=$(signal "$entry" Extensions) names=$(signal "$entry" Names) paths=$(signal "$entry" Paths)
  tool='' pin='' route='' run='' skip='' only=''
  while IFS= read -r line; do
    case $line in
      '### '* | '## '* | __END__)
        [ -n "$tool" ] && { trial "$entry" "$tool" "$pin" "$route" "$run" "$skip" "$only" < /dev/null || rc=1; }
        tool='' pin='' route='' run='' skip='' only=''
        case $line in '### '*) tool=${line#\#\#\# } ;; esac ;;
      'Pin: '*) pin=${line#Pin: } ;;
      'Files: '*) only=${line#Files: } ;;
      'Route: '*) route=$(cmd "$line") ;;
      'Run: '*) run=$(cmd "$line") ;;
      'Unavailable: '*) skip="unavailable (${line#Unavailable: })" ;;
      'Local-only: '*) skip="local-only (${line#Local-only: })" ;;
    esac
  done <<EOF
$(cat "$catalog/$entry.md")
__END__
EOF
done
exit $rc
