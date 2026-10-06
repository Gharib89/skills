#!/usr/bin/env bash
# host_pr_requested_at over the real GitHub adapter: the latest instant a
# reviewer was asked for a round, which `poll-pr --reviewer` takes as its default
# --since. On the host's own request call it is the latest `review_requested`
# timeline event for the reviewer, under any name the host records it as; under
# a comment transport it is the latest PR comment opening with the phrase, by
# anyone. A fake `gh` answers per route, so no case reaches a host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
bin=$work/bin; mkdir -p "$bin"
export FAKE=$work/fake; mkdir -p "$FAKE"
# Each route answers what its own `--jq` would have printed: the timeline's
# events as the adapter's filter shapes them, the comments as raw objects.
cat > "$bin/gh" <<'GH'
#!/usr/bin/env bash
case " $* " in
  */timeline*) body=$(cat "$FAKE/timeline") ;;
  */issues/7/comments*) body=$(cat "$FAKE/comments") ;;
  *) echo "fake gh: unexpected call: $*" >&2; exit 1 ;;
esac
printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n%s\n' "$body"
GH
chmod +x "$bin/gh"
export PATH=$bin:$PATH
export SHIP_OWNER=o SHIP_REPO=r SHIP_REPO_SLUG=o/r
source skills/ship/scripts/_lib.sh
source skills/ship/scripts/host/github.sh

ev() { jq -cn --arg e "$1" --arg l "$2" --arg t "$3" '{event: $e, login: $l, created_at: $t}'; }
timeline() { printf '%s\n' "$@" > "$FAKE/timeline"; }
comment() { jq -cn --arg b "$1" --arg u "$2" --arg t "$3" '{body: $b, user: {login: $u}, created_at: $t}'; }

timeline "$(ev review_requested claude 2026-09-17T10:00:00Z)" \
         "$(ev reviewed claude 2026-09-17T10:05:00Z)" \
         "$(ev review_requested someone-else 2026-09-17T11:00:00Z)" \
         "$(ev review_requested claude 2026-09-17T12:00:00Z)"
check "the latest request for that reviewer, another's later one ignored, [bot] suffix or not" \
  2026-09-17T12:00:00Z "$(host_pr_requested_at 7 'Claude[bot]')"
check "Copilot is found under the name the host records it as" 2026-09-17T09:00:00Z \
  "$(timeline "$(ev review_requested Copilot 2026-09-17T09:00:00Z)"; host_pr_requested_at 7 'copilot-pull-request-reviewer[bot]')"

timeline "$(ev review_requested someone-else 2026-09-17T11:00:00Z)"
host_pr_requested_at 7 'claude[bot]' >/dev/null; check_rc "a reviewer never requested has no instant" 1 $?

{ comment '@claude' alice 2026-09-17T10:00:00Z
  comment '@claude please look again' bob 2026-09-17T12:00:00Z
  comment 'looks good, thanks @claude' alice 2026-09-17T13:00:00Z
  comment 'unrelated' claude[bot] 2026-09-17T14:00:00Z; } > "$FAKE/comments"
check "a comment transport reads the latest comment that opens with the phrase, by any author" \
  2026-09-17T12:00:00Z "$(host_pr_requested_at 7 'claude[bot]' '@claude')"
comment 'nothing relevant' alice 2026-09-17T10:00:00Z > "$FAKE/comments"
host_pr_requested_at 7 'claude[bot]' '@claude' >/dev/null; check_rc "no comment with the phrase has no instant" 1 $?

finish
