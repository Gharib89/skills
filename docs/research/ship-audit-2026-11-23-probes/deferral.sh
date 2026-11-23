#!/usr/bin/env bash
set -uo pipefail
src=$PWD/skills/ship/scripts
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
repo=$work/repo
git init -q -b main "$repo"
git -C "$repo" remote add origin https://github.com/example/test
export XDG_STATE_HOME=$work/state SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$SHIP_FAKE" "$repo/docs/agents"
cat > "$repo/docs/agents/ship.md" <<'EOF'
## CI

Legs: None.
No-checks legal: yes

## Reviewers

None.
EOF
A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
record=$(cd "$repo" && bash -c 'source "$1"; ship_record_root' _ "$src/_lib.sh")
mkdir -p "$record/ship-42"
printf '## Local gate\n- 12:00 %s pass {"secrets":"deferred-to-ci"}\n' "$A" > "$record/ship-42/run.md"
ci="$record/ship-42/ci-wait.json"
jq -n --arg a "$A" ' {status:"no-checks", head_sha:$a, checks:[]}' > "$ci"
jq -n --arg a "$A" '{number:7,title:"fix: x",head_ref:"fix/x",base_ref:"main",head_sha:$a,state:"open"}' > "$SHIP_FAKE/host_pr_get.1.json"
jq -n '{number:42,title:"Fixture",state:"open",body:"## Acceptance Criteria\n- [ ] Implement the missing feature",labels:[],assignees:[],is_pr:false}' > "$SHIP_FAKE/host_issue_get.1.json"
printf "[]\n" > "$SHIP_FAKE/host_issue_comments.1.json"; printf "[]\n" > "$SHIP_FAKE/host_issue_blockers_open.1.json"
cd "$repo" || exit 2
bash "$src/run-file.sh" gate clean "$ci" --head "$A" --file "$record/ship-42/run.md" 2>/dev/null
