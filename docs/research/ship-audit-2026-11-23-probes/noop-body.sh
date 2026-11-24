#!/usr/bin/env bash
set -eu -o pipefail
src=$PWD/skills/ship-run/scripts
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q -b main "$work/repo"
git -C "$work/repo" remote add origin https://github.com/example/repo
cat >"$work/adapter" <<'EOF'
host_pr_get() { jq -n --rawfile b "$PROBE_BODY" '{body:$b}'; }
host_pr_set_body() {
  cmp -s "$2" "$PROBE_BODY" && printf 'identical PR body PATCH requested\n' >&2
  diff -u "$PROBE_BODY" "$2" >&2; return 0
}
EOF
printf '## Review\n\nAlready recorded.\n\n' > "$work/body.md"
printf 'Already recorded.\n' > "$work/section.md"
export SHIP_HOST_ADAPTER=$work/adapter PROBE_BODY=$work/body.md
(cd "$work/repo" && bash "$src/update-pr-body.sh" 7 --section Review --body-file "$work/section.md")
