#!/usr/bin/env bash
# poll-pr and a round the host never queued: once a settle has passed since
# `--since`, a since-rule poll under the host's request transport asks the host
# whether the awaited reviewer has a request on record since then, and a `false`
# closes the window at once with `never_queued: true` and done=false. From #266
# on, a quota-out Copilot left no request event and no notice, and the free-round
# poll waited its whole 600 s window (#273) before the loop's first request read
# back never-queued within seconds (#284).
#
# Driven end to end over the Host fake and a throwaway repo whose origin names
# GitHub, so the mechanic's own loop is the subject: no case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/poll-pr.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo
export SHIP_FAKE=$work/fake SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
mkdir -p "$repo/docs/agents" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
cat > "$repo/docs/agents/ship.md" <<'EOF'
## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-request
Request: None.
Workflow: None.
Cap: 3
Gating: no
Fallback-for: None.

### claude

Login: claude[bot]
Trigger: on-request
Request: comment @claude
Workflow: .github/workflows/claude-review.yml
Cap: 2
Gating: no
Fallback-for: copilot

### pusher

Login: copilot-pull-request-reviewer[bot]
Trigger: on-push
Request: None.
Workflow: None.
Cap: None.
Gating: no
Fallback-for: None.

## Coding standards
EOF

login='copilot-pull-request-reviewer[bot]'
# The clock poll-pr reads the settle against, held by a `date` stub: a PR opened
# two minutes before it is past the settle, one opened at it is not.
clock=1790000000
mkdir -p "$work/bin"
cat > "$work/bin/date" <<STUB
#!/usr/bin/env bash
[ "\$1 \$2" = "-u +%s" ] && { echo $clock; exit 0; }
exec /usr/bin/env -i PATH=/usr/bin:/bin date "\$@"
STUB
chmod +x "$work/bin/date"
at() { jq -rn --argjson t "$1" '$t | todate'; }
old=$(at $((clock - 120))) new=$(at "$clock") posted=$(at $((clock - 60)))

reset() {
  rm -f "$SHIP_FAKE"/*
  jq -cn '{number: 7, url: "https://example.invalid/7", title: "t", body: "",
    head_sha: "deadbee", head_ref: "fix/x-7", base_ref: "main", state: "open", mergeable: "clean"}' \
    > "$SHIP_FAKE/host_pr_get.1.json"
  printf '[]\n' > "$SHIP_FAKE/host_pr_checks.1.json"
  printf 'me\n' > "$SHIP_FAKE/host_identity.1.json"
  printf '{"on_head":[],"all":[],"total":0}\n' > "$SHIP_FAKE/host_pr_reviews.1.json"
  echo null > "$SHIP_FAKE/host_pr_reviewer_blocked.1.json"
}
queued() { printf '%s\n' "$1" > "$SHIP_FAKE/host_pr_review_queued.1.json"; }
poll() { ( cd "$repo" && PATH="$work/bin:$PATH" bash "$mech" 7 "$@" ); }
calls() { cat "$SHIP_FAKE/host_$1.n" 2>/dev/null || echo 0; }

# The free-round poll #273 made: nothing queued, and the window closes on the
# host's record rather than on the clock.
reset; queued false
out=$(poll --reviewer copilot --since "$old" --timeout 10 --interval 1); rc=$?
check_rc "a round never queued closes the window" 1 "$rc"
check "with never_queued set and done false" 'true false' \
  "$(jq -r '[(.never_queued|tostring), (.done|tostring)] | join(" ")' <<<"$out")"
check "and none of the window is spent" true "$(jq -r '.waited_s < 5' <<<"$out")"
check "the read names the reviewer's login and the --since" \
  "host_pr_review_queued	7	$login	$old" "$(grep '^host_pr_review_queued' "$SHIP_FAKE/calls")"
check "and the refusal path stays out of it" null "$(jq -r .refused_by <<<"$out")"

# --brief is what the loop reads, so the signal travels in it.
reset; queued false
out=$(poll --reviewer copilot --since "$old" --timeout 10 --interval 1 --brief)
check "--brief carries never_queued" true "$(jq -r .never_queued <<<"$out")"

# A queued round with nothing posted yet keeps today's window, and the read is
# not repeated once the host has answered queued.
reset; queued true
out=$(poll --reviewer copilot --since "$old" --timeout 2 --interval 1); rc=$?
check_rc "a queued round holds the window to --timeout" 1 "$rc"
check "never_queued reads false" false "$(jq -r .never_queued <<<"$out")"
check "the window ran its course" true "$(jq -r '.waited_s >= 2' <<<"$out")"
check "the queued read is made once" 1 "$(calls pr_review_queued)"

# A queued round refused with a quota notice is still `degraded: blocked`.
reset; queued true
notice='Copilot was unable to review this pull request because the user who requested the review has reached their quota limit.'
jq -cn --arg b "$notice" --arg l "$login" --arg at "$posted" \
  '{id: "1", login: $l, state: "comment", submitted_at: $at, body: $b} as $r
   | {on_head: [$r], all: [$r], total: 1}' > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(poll --reviewer copilot --since "$old" --interval 30); rc=$?
check_rc "a refused round closes the window" 1 "$rc"
check "as refused_by, not never_queued" 'since true' \
  "$(jq -r '[.refused_by, (.never_queued != true | tostring)] | join(" ")' <<<"$out")"

# Inside the settle the host's event may not have landed yet: no read.
reset; queued false
out=$(poll --reviewer copilot --since "$new" --timeout 0 --interval 1)
check "no read inside the settle" 0 "$(calls pr_review_queued)"
check "and never_queued stays null" null "$(jq -r .never_queued <<<"$out")"

# A host that cannot answer leaves the window as it was.
reset; touch "$SHIP_FAKE/host_pr_review_queued.1.fail"
out=$(poll --reviewer copilot --since "$old" --timeout 0 --interval 1)
check "an unanswered read is null" null "$(jq -r .never_queued <<<"$out")"

# The comment transport has no request event to read: the run read is its signal.
reset; queued false
out=$(poll --reviewer claude --since "$old" --timeout 0 --interval 1)
check "under the comment transport the read is never made" 0 "$(calls pr_review_queued)"
check "and never_queued stays null" null "$(jq -r .never_queued <<<"$out")"

# The head rule has no --since to key the read to.
reset; queued false
out=$(poll --reviewer pusher --timeout 0 --interval 1)
check "under the head rule the read is never made" 0 "$(calls pr_review_queued)"

# A landed round needs no answer about the queue.
reset; queued false
jq -cn --arg l "$login" --arg at "$posted" \
  '{id: "2", login: $l, state: "comment", submitted_at: $at, body: "- a finding"} as $r
   | {on_head: [$r], all: [$r], total: 1}' > "$SHIP_FAKE/host_pr_reviews.1.json"
out=$(poll --reviewer copilot --since "$old" --interval 30); rc=$?
check_rc "a landed round is done" 0 "$rc"
check "with no queued read" 0 "$(calls pr_review_queued)"

finish
