#!/usr/bin/env bash
# run-file for a fixture whose Run file and CI answer name a head no commit has
# (the label abcdef0123456789). A `gate` verb run inside RUN_FILE_HEAD_REPO gets
# that profile committed (tests/run-file-lib.sh), the label swapped for the
# commit in its arguments, file arguments, a `--scratchpad`'s Run files and `-` stdin, and the commit swapped
# back for the label in the files and in what it prints, so the fixture's own
# strings stay as they are. Every other verb runs unchanged. Not run directly:
# tests/run-file-lib.sh sets RUN_FILE_REAL, RUN_FILE_HEAD_REPO and
# RUN_FILE_HEAD_ORIGIN.
set -uo pipefail
# shellcheck source=run-file-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/run-file-lib.sh"
label=abcdef0123456789
real=$(run_file_commit_profile "$RUN_FILE_HEAD_REPO" "$RUN_FILE_HEAD_ORIGIN" 2>/dev/null)
if [ "${1:-}" != gate ] || [ "$PWD" != "$RUN_FILE_HEAD_REPO" ] || [ -z "$real" ]; then
  exec bash "$RUN_FILE_REAL" "$@"
fi
files=() stdin=no prev=
for a; do
  [ -f "$a" ] && files+=("$a")
  [ "$a" = - ] && stdin=yes
  # An issue lookup reads the Run file under the scratchpad, never named.
  [ "$prev" = --scratchpad ] && [ -d "$a" ] && for f in "$a"/*/run.md; do [ -f "$f" ] && files+=("$f"); done
  prev=$a
done
# Rewrites in place through cat, which needs the file's permission, not its directory's.
retag() { # retag <from> <to> <file>...
  local from=$1 to=$2 f t=$tmp_dir/retag
  shift 2
  for f; do sed "s/$from/$to/g" "$f" > "$t" && cat "$t" > "$f"; done
}
tmp_dir=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp_dir"' EXIT
retag "$label" "$real" "${files[@]}"
if [ "$stdin" = yes ]; then sed "s/$label/$real/g" > "$tmp_dir/stdin"; else : > "$tmp_dir/stdin"; fi
bash "$RUN_FILE_REAL" "${@//$label/$real}" < "$tmp_dir/stdin" > "$tmp_dir/out" 2> "$tmp_dir/err"
rc=$?
retag "$real" "$label" "${files[@]}"
sed "s/$real/$label/g" "$tmp_dir/out"
sed "s/$real/$label/g" "$tmp_dir/err" >&2
exit "$rc"
