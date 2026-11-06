#!/usr/bin/env bash
# Every super-agent script a SKILL.md step runs is executable in the index, in the
# source tree and in the derived copy: a 100644 script answers `Permission
# denied` when run by path, as the first real run found.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

for tree in skills/super-agent .claude/skills/super-agent; do
  scripts=$(git ls-files -s "$tree/scripts" | awk '$4 ~ /\.sh$/ && $4 !~ /\/_lib\.sh$/ { print $1 }' | sort | uniq -c)
  count=$(git ls-files "$tree/scripts" | grep -c '\.sh$')
  check "$tree: every script but _lib.sh is 100755 in the index" "$((count - 1)) 100755" "$(sed 's/^ *//' <<<"$scripts")"
done

finish
