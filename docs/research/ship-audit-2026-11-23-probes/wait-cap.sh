#!/usr/bin/env bash
set -eu -o pipefail
src=$PWD/skills/ship-run/scripts
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q -b main "$work/repo"
git -C "$work/repo" remote add origin https://dev.azure.com/example/project/_git/repo
mkdir -p "$work/repo/docs/agents"
cat > "$work/repo/docs/agents/ship.md" <<'EOF'
## CI

Legs: custom/build: External builder
No-checks legal: yes
EOF
cat > "$work/adapter" <<'EOF'
source "$SHIP_SCRIPTS/host/ado.d/prs.sh"
ORG=()
azx() {
  if [[ $1 == repos && $2 == pr && $3 == policy && $4 == list ]]; then printf '[]\n'; else return 99; fi
}
invoke() {
  [[ $1 == GET && $2 == git && $3 == pullRequestStatuses ]] || return 99
  [[ ${STATUS_CASE:-} != unavailable ]] || return 1
  printf '{"value":[{"iterationId":1,"id":1,"state":"succeeded","context":{"genre":"custom","name":"build"},"creationDate":"2026-10-01T00:00:00Z"}]}\n'
}
host_pr_get() { sleep 2; printf '{"number":7,"head_ref":"fix/x","base_ref":"main","head_sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","mergeable":"clean","state":"open"}\n'; }
EOF
export SHIP_CALL_CAP=1 SHIP_HOST_ADAPTER=$work/adapter SHIP_CI_WAIT_GRACE=0
cd "$work/repo"
echo 'Scenario: host_pr_get takes 2 s under a 1 s call cap (SHIP_CALL_CAP=1).'
bash "$src/ci-wait.sh" 7 --sha bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb --timeout 60 | jq -c '{status,head_sha,checks}'
