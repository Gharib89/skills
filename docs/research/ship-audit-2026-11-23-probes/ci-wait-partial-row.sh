#!/usr/bin/env bash
# ci-wait over the Host fake when the one check row for the profile's leg carries
# a name and no status. The control row carries `pending`. Run from the repo root.
set -uo pipefail
mech=$PWD/skills/ship/scripts/ci-wait.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
repo=$work/repo
mkdir -p "$SHIP_FAKE" "$repo/docs/agents"
printf '# Ship profile\n\n## CI\n\nLegs: test: npm test\nNo-checks legal: no\nPush policy: Default.\n\n## Reviewers\n' \
  > "$repo/docs/agents/ship.md"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
ci() { ( cd "$repo" && SHIP_CI_WAIT_GRACE=1 bash "$mech" 7 --interval 1 --timeout 3 2>/dev/null | jq -c '{status, failing, missing_legs}'; echo "rc=${PIPESTATUS[0]}" ); }

echo 'A row with a name and no status: [{"name":"test"}]'
printf '[{"name":"test"}]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
ci
rm -f "$SHIP_FAKE"/*
echo 'Control, the same row still pending: [{"name":"test","status":"pending"}]'
printf '[{"name":"test","status":"pending"}]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
ci
