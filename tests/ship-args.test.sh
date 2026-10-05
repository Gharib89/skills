#!/usr/bin/env bash
# `ship_args`, the one argument check every mechanic runs after `ship_help`:
# an `<issue>` or `<pr>` is a number, a positional never starts with `-`, and a
# `--body-file` names a readable regular file. Each refusal is the mechanic's
# usage line at exit 2 before `ship_load_host`, which the marker adapter proves:
# it records being sourced, and a refusal leaves it unrecorded.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

dir=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'chmod 600 "$work/locked.md" 2>/dev/null; rm -rf "$work"' EXIT
repo=$work/repo
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
loaded=$work/loaded
printf ': > "%s"\n' "$loaded" > "$work/adapter.sh"
export SHIP_HOST_ADAPTER=$work/adapter.sh

readable=$work/body.md; printf 'body\n' > "$readable"
unreadable=$work/locked.md; printf 'body\n' > "$unreadable"
# Root reads any file, so a mode-000 body proves nothing there: the chmod and the
# case that relies on it run together, off root only.
[ "$(id -u)" -eq 0 ] || chmod 000 "$unreadable"

# <case> <mechanic> <args...>: the usage error, exit 2, adapter never sourced.
refused() {
  local name=$1 m=$2 out rc want; shift 2
  rm -f "$loaded"
  out=$(cd "$repo" && bash "$dir/$m.sh" "$@" 2>/dev/null); rc=$?
  want=$(bash "$dir/$m.sh" --help)
  check "$name: the usage line" "$want" "$(jq -r '.error // empty' <<<"$out")"
  check_rc "$name: tooling" 2 "$rc"
  check "$name: the adapter was not loaded" absent "$([ -e "$loaded" ] && echo loaded || echo absent)"
}

refused "resolve-thread, a non-numeric PR"              resolve-thread abc 1
refused "reply-thread, a non-numeric PR"                reply-thread abc 1 --body-file "$readable"
refused "reply-thread, a body file that is a directory" reply-thread 1 t1 --body-file "$work"
refused "comment-pr, a non-numeric PR"                  comment-pr abc --body-file "$readable"
refused "read-issue, a non-numeric issue"               read-issue abc
refused "cleanup, an issue that is neither a number nor none" cleanup abc
refused "merge, a non-numeric issue"                    merge 1 abc
refused "isolate, a flag as the slug"                   isolate 1 feat --slug
refused "read-pr, an empty PR"                          read-pr ""
refused "manage-issue, a flag in the verb slot"         manage-issue 1 --json
# A flag in the first slot is scripts/contract-check.sh check 4's. The id match
# is anchored and admits `none` only where the kind names it.
refused "read-issue, an id with a letter in it"         read-issue 12a
refused "read-issue, a signed id"                       read-issue +3
refused "read-issue, an id with a space in it"          read-issue "1 2"
refused "read-pr, none where only a PR fits"            read-pr none
refused "reflect, none where only an issue fits"        reflect none 1
refused "comment-pr, --body-file with no value"         comment-pr 1 --body-file
# The scan reads every `--body-file` word as the flag, whatever precedes it.
refused "open-pr, --body-file as the title's value"     open-pr 1 --title --body-file
# root reads any file, so a mode-000 body proves nothing there.
if [ "$(id -u)" -ne 0 ]; then
  refused "comment-pr, an unreadable body file"         comment-pr 1 --body-file "$unreadable"
else
  skipped "comment-pr, an unreadable body file"
fi

# `none` is the task-spec run's issue wherever a mechanic names it.
out=$(cd "$repo" && bash "$dir/cleanup.sh" none 2>/dev/null)
check "cleanup accepts none" "" "$(jq -r '.error // empty' <<<"$out")"

finish
