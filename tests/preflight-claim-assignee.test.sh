#!/usr/bin/env bash
# A ticket a super agent claimed (a `super-agent-claim` comment, no assignee)
# passes Ship's preflight, while one assigned to anyone with no claim comment
# still stops with `already claimed`: Ship's assignee check is the contract
# `skills/super-agent`'s claim relies on by never assigning (#1125).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
real_git=$(command -v git)
g() { "$real_git" -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
export GIT_ALLOW_PROTOCOL=file
mkdir -p "$SHIP_FAKE" "$work/bin"
{
  g init -q --bare "$work/origin.git"
  g clone -q "$work/origin.git" "$work/repo"
  cd "$work/repo"
  g commit -q --allow-empty -m init && g push -q origin main
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
cat > "$work/bin/git" <<SHIM
#!/usr/bin/env bash
[ "\$*" = "remote get-url origin" ] && { echo https://github.com/owner/repo.git; exit 0; }
exec "$real_git" "\$@"
SHIM
chmod +x "$work/bin/git"

printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"
claim='{"author":"me","writer":true,"body":"<!-- super-agent-claim machine=m thread=t -->\nClaimed."}'
issue() { # <assignees json>
  jq -n --argjson a "$1" --argjson c "$claim" \
    '{number: 5, state: "open", is_pr: false, title: "t", body: "", labels: ["ready-for-agent"], assignees: $a, comments: [$c], blockers: []}' \
    > "$SHIP_FAKE/host_issue_get.1.json"
}
claimed_reasons() { ( cd "$work/repo" && PATH="$work/bin:$PATH" bash "$scripts/preflight.sh" 5 2>/dev/null ) \
  | jq -c '[.reasons[] | select(startswith("already claimed"))]'; }

issue '[]'
check "a ticket with only a super-agent claim comment passes" '[]' "$(claimed_reasons)"
issue '["other"]'
check "an assignee with no claim comment of its own still stops" '["already claimed: other"]' "$(claimed_reasons)"

finish
