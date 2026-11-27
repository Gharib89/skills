#!/usr/bin/env bash
# A plain `preflight <n>` reads two stale shapes as what they are (#1427):
# - a closing PR that is merged or closed is history on a reopened issue, not
#   competing work: no `existing PR` reason, one warning naming it. An open
#   closing PR still stops the run.
# - a claim with no `*-<n>` branch on origin and no open closing PR still stops
#   with `already claimed`, and says so, so the human rules on it at a glance.
#   A claim with a branch or an open PR behind it reads as before.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

scripts=$PWD/skills/ship-run/scripts
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
real_git=$(command -v git)
g() { "$real_git" -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
export GIT_ALLOW_PROTOCOL=file
mkdir -p "$work/bin"
{
  g init -q --bare "$work/origin.git"
  g clone -q "$work/origin.git" "$work/repo"
  cd "$work/repo"
  g commit -q --allow-empty -m init && g push -q origin main
} >/dev/null 2>&1 || { echo "fixture setup failed" >&2; exit 2; }
cd - >/dev/null || exit 2
cat > "$work/bin/git" <<SHIM
#!/usr/bin/env bash
[ "\$*" = "remote get-url origin" ] && { echo https://github.com/owner/repo.git; exit 0; }
exec "$real_git" "\$@"
SHIM
chmod +x "$work/bin/git"

fixture() { # <assignees json> <closing json>
  rm -rf "$SHIP_FAKE"; mkdir -p "$SHIP_FAKE"
  printf 'me\n'   > "$SHIP_FAKE/host_identity.1.json"
  printf 'true\n' > "$SHIP_FAKE/host_can_push.1.json"
  jq -n --argjson a "$1" '{number: 5, state: "open", is_pr: false, labels: ["ready-for-agent"], assignees: $a}' \
    > "$SHIP_FAKE/host_issue_get.1.json"
  jq -n --argjson c "$2" '{closing: $c, mentions: []}' > "$SHIP_FAKE/host_issue_linked_prs.1.json"
}
preflight() { ( cd "$work/repo" && PATH="$work/bin:$PATH" bash "$scripts/preflight.sh" 5 2>/dev/null ); }
stops() { jq -c '[.reasons[] | select(test("^(already claimed|existing PR|existing branch)"))]' <<<"$1"; }
notes() { jq -c '[.warnings[] | select(startswith("closing PR"))]' <<<"$1"; }

fixture '[]' '[{"number": 9, "state": "merged"}]'
out=$(preflight)
check "a merged closing PR is no stop" '[]' "$(stops "$out")"
check "and is named in a warning" '["closing PR #9 (merged) is not open: history, not competing work"]' "$(notes "$out")"

fixture '[]' '[{"number": 9, "state": "closed"}, {"number": 11, "state": "open"}]'
out=$(preflight)
check "an open closing PR beside a closed one still stops" '["existing PR: #11 (open)"]' "$(stops "$out")"
check "and the closed one is a warning" '["closing PR #9 (closed) is not open: history, not competing work"]' "$(notes "$out")"

fixture '["other"]' '[{"number": 9, "state": "merged"}]'
check "a claim with no branch and no open PR says so" \
  '["already claimed: other (no *-5 branch on origin, no open closing PR)"]' "$(stops "$(preflight)")"

fixture '["other"]' '[{"number": 9, "state": "open"}]'
check "a claim with an open PR reads as before" \
  '["already claimed: other","existing PR: #9 (open)"]' "$(stops "$(preflight)")"

g -C "$work/repo" push -q origin main:fix/y-5 2>/dev/null
fixture '["other"]' '[]'
check "a claim with a branch reads as before" \
  '["already claimed: other","existing branch: fix/y-5"]' "$(stops "$(preflight)")"

finish
