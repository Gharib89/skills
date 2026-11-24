#!/usr/bin/env bash
# The clean gate grades against the checkout's copy of the ship profile. The
# branch commits no profile change; an uncommitted edit that drops the reviewer
# turns the same evidence from held to clean. Run from the repo root.
set -uo pipefail
src=$PWD/skills/ship-run/scripts
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
origin=$work/github.com/owner/repo.git
repo="$work/repo"
feature="$work/feature"
export XDG_STATE_HOME="$work/state" SHIP_FAKE="$work/fake" SHIP_HOST_ADAPTER="$PWD/tests/host-fake.sh" GIT_ALLOW_PROTOCOL=file
mkdir -p "$SHIP_FAKE"
git init -q --bare -b main "$origin"
git clone -q "$origin" "$repo" 2>/dev/null
g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
mkdir -p "$repo/docs/agents"
cat > "$repo/docs/agents/ship.md" <<'PROFILE'
## CI

Legs: build: build
No-checks legal: no

## Reviewers

### Primary
Trigger: on-request

## PR

Merge: on-clean-gate
PROFILE
g add docs/agents/ship.md; g commit -q -m base
g push -q origin main
g remote set-head origin main
g worktree add -qb fix/x "$feature" main
git -C "$feature" -c user.name=t -c user.email=t@t commit -q --allow-empty -m change
A=$(git -C "$feature" rev-parse HEAD)
git -C "$feature" push -q origin fix/x
record=$(cd "$repo" && bash -c 'source "$1"; ship_record_root' _ "$src/_lib.sh")
mkdir -p "$record/ship-case"
printf '## Local gate\n- 12:00 %s pass {"secrets":"pass"}\n' "$A" > "$record/ship-case/run.md"
jq -n --arg a "$A" '{status:"green", head_sha:$a, checks:[{name:"build",status:"success"}]}' > "$work/ci.json"
gate() { (cd "$feature" && bash "$src/run-file.sh" gate clean "$work/ci.json" --head "$A" --issue case 2>/dev/null | jq -c .; echo "rc=${PIPESTATUS[0]}"); }

echo 'Clean gate with the committed profile:'
gate
sed -i '/^### Primary$/,/^Trigger: on-request$/c\None.' "$feature/docs/agents/ship.md"
echo 'Clean gate after an uncommitted edit drops the reviewer:'
gate
echo "Committed profile changes on the branch: $(git -C "$feature" diff --name-only main HEAD -- docs/agents/ship.md | wc -l | tr -d ' ')"
echo "Uncommitted: $(git -C "$feature" status --porcelain -- docs/agents/ship.md)"
