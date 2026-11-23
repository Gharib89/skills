#!/usr/bin/env bash
set -uo pipefail
src=$PWD/skills/ship/scripts
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
origin=$work/github.com/owner/repo.git
repo="$work/repo"
feature="$work/feature"
export XDG_STATE_HOME="$work/state" SHIP_FAKE="$work/fake" SHIP_HOST_ADAPTER="$PWD/tests/host-fake.sh" SHIP_MERGE_CHECKS_GRACE=0 GIT_ALLOW_PROTOCOL=file
mkdir -p "$SHIP_FAKE"
git init -q --bare -b main "$origin"
git clone -q "$origin" "$repo" 2>/dev/null
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
mkdir -p "$repo/docs/agents"
cat > "$repo/docs/agents/ship.md" <<'EOF'
## CI

Legs: build: build
No-checks legal: no

## Reviewers

### Primary
Trigger: on-request

## PR

Merge: Default.
EOF
g add docs/agents/ship.md; g commit -q -m base
g push -q origin main
g remote set-head origin main
g worktree add -qb fix/x "$feature" main
cat > "$feature/docs/agents/ship.md" <<'EOF'
## CI

Legs: build: build
No-checks legal: no

## Reviewers

None.

## PR

Merge: on-clean-gate
EOF
git -C "$feature" -c user.name=t -c user.email=t@t commit -qam change
A=$(git -C "$feature" rev-parse HEAD)
git -C "$feature" push -q origin fix/x
record=$(cd "$repo" && bash -c 'source "$1"; ship_record_root' _ "$src/_lib.sh")
mkdir -p "$record/ship-case"
printf '## Local gate\n- 12:00 %s pass {"secrets":"pass"}\n' "$A" > "$record/ship-case/run.md"
jq -n --arg a "$A" ' {status:"green", head_sha:$a, checks:[{name:"build",status:"success"}]}' > "$work/ci.json"
printf '[{"name":"build","status":"success"}]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
pr() { jq -n --arg s "$2" --arg a "$A" '{number:7,title:"fix: x",head_ref:"fix/x",base_ref:"main",head_sha:$a,state:$s}' > "$SHIP_FAKE/host_pr_get.$1.json"; }
pr 1 open; pr 2 merged
echo 'Clean gate against main checkout profile:'
(cd "$repo" && bash "$src/run-file.sh" gate clean "$work/ci.json" --head "$A" --issue case 2>/dev/null)
echo 'Clean admission against feature worktree profile:'
(cd "$feature" && bash "$src/run-file.sh" gate admit clean "$work/ci.json" --head "$A" --issue case)
echo 'Merge under same CI policy with no host reviewer or human merge word:'
(cd "$feature" && bash "$src/merge.sh" 7 none "$A" --run case)
rg '^host_pr_merge' "$SHIP_FAKE/calls"
