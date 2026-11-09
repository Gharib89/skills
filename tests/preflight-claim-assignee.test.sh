#!/usr/bin/env bash
# A ticket claimed by super-agent's real `claim.sh` (run over the fake `gh` of
# tests/super-agent-fake.sh) passes Ship's preflight, the issue built from what
# that run recorded: its posted comment and every assignee it set. So a claim
# that assigned again would stop here. A ticket assigned to anyone with no claim
# comment still stops with `already claimed` (#1125).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh
source tests/super-agent-fake.sh

root=$PWD
scripts=$root/skills/ship/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
real_git=$(command -v git)
g() { "$real_git" -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$root/tests/host-fake.sh
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
issue() { # <assignees json> <comments json>
  jq -n --argjson a "$1" --argjson c "$2" \
    '{number: 5, state: "open", is_pr: false, title: "t", body: "", labels: ["ready-for-agent"], assignees: $a, comments: $c, blockers: []}' \
    > "$SHIP_FAKE/host_issue_get.1.json"
}
# claim: run the real claim.sh on owner/repo#5 and leave what it did in $claimed_*.
claim() {
  export SA_FAKE=$work/sa; mkdir -p "$SA_FAKE/gh" "$work/sabin"; rm -f "$SA_FAKE/calls"
  sa_fake_install "$work/sabin"
  sa_route repos/owner/repo/issues/5/comments '[]'; sa_route user '{"login":"me"}'
  echo 2026-11-09T12:00:00Z > "$SA_FAKE/now"
  PATH="$work/sabin:$PATH" bash "$root/skills/super-agent/scripts/claim.sh" --repo owner/repo --number 5 \
    --machine m --thread t >/dev/null 2>&1 || { echo "claim.sh failed" >&2; exit 2; }
  claimed_assignees=$(sed -n 's/.*assignees\[\]=\(.*\)$/\1/p' "$SA_FAKE/calls" | jq -Rsc 'split("\n") | map(select(. != "")) | unique')
  claimed_comments=$(jq -c 'map({author: .user.login, writer: true, body})' \
    "$SA_FAKE/gh/$(printf '%s' repos/owner/repo/issues/5/comments | sed 's/[^A-Za-z0-9._-]/_/g')")
}
claimed_reasons() { ( cd "$work/repo" && PATH="$work/bin:$PATH" bash "$scripts/preflight.sh" 5 2>/dev/null ) \
  | jq -c '[.reasons[] | select(startswith("already claimed"))]'; }

claim
check "claim.sh left a claim comment and no assignee" '[1,[]]' "$(jq -c '[length, .] | [.[0], '"$claimed_assignees"']' <<<"$claimed_comments")"
issue "$claimed_assignees" "$claimed_comments"
check "a ticket claimed by claim.sh passes" '[]' "$(claimed_reasons)"
issue '["other"]' '[]'
check "an assignee with no claim comment of its own still stops" '["already claimed: other"]' "$(claimed_reasons)"

finish
