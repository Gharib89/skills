#!/usr/bin/env bash
set -eu -o pipefail
src=$PWD/skills/ship-run/scripts
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q -b main "$work/repo"
git -C "$work/repo" remote add origin https://github.com/example/repo
cat > "$work/adapter" <<'EOF'
host_identity() { printf 'shared-bot\n'; }
host_issue_get() {
  if [[ -e "$CLAIM_PROBE_DIR/read.$RUN" ]]; then
    printf '{"assignees":["shared-bot"]}\n'
  else
    : > "$CLAIM_PROBE_DIR/read.$RUN"
    for attempt in {1..100}; do
      [[ -e "$CLAIM_PROBE_DIR/read.one" && -e "$CLAIM_PROBE_DIR/read.two" ]] && break
      sleep .02
    done
    [[ -e "$CLAIM_PROBE_DIR/read.one" && -e "$CLAIM_PROBE_DIR/read.two" ]] || return 1
    printf '{"assignees":[]}\n'
  fi
}
host_issue_assign() { printf '%s assigned %s by run %s\n' "$1" "$2" "$RUN" >> "$CLAIM_PROBE_DIR/calls"; }
host_issue_comment() { printf '%s claimed by run %s\n' "$1" "$RUN" >> "$CLAIM_PROBE_DIR/calls"; }
EOF
export CLAIM_PROBE_DIR=$work SHIP_HOST_ADAPTER=$work/adapter
cd "$work/repo"
RUN=one bash "$src/manage-issue.sh" 42 take --fresh > "$work/one" & one=$!
RUN=two bash "$src/manage-issue.sh" 42 take --fresh > "$work/two" & two=$!
wait "$one"; wait "$two"
jq -c . "$work/one" "$work/two"
cat "$work/calls"
