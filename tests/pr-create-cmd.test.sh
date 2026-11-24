#!/usr/bin/env bash
# The adapters' PR-create pieces (#1239): host_pr_create_body (the body the PR
# opens with, the host's closing link added) and host_pr_create_cmd (the one
# command line the agent runs as its own Bash call, so Claude Code's
# `claude_code.pull_request.count` sees the create). Each command is run as
# printed by `bash -c`, the way the agent's Bash call runs it, against a fake
# `gh` or `az` on PATH that records its argv one word per line, so what the
# host would receive is what every case asserts on and nothing reaches a host.
# host_pr_get's created_at, which the verify call answers with, is read the
# same way.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
export ARGV_LOG=$work/argv
for tool in gh az; do
  cat > "$work/$tool" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGV_LOG"
FAKE
  chmod +x "$work/$tool"
done
body=$work/body.md
printf '## Summary\n\nit\x27s "quoted" $HOME\n' > "$body"
title='fix(ship): a "title" with $dollar and spaces'
argv() { PATH=$work:$PATH bash -c "$1" >/dev/null 2>&1; cat "$ARGV_LOG"; }

# Each host runs in a subshell, since both adapters define the same names; a
# failing case there carries out through the subshell's exit.

# --- GitHub ------------------------------------------------------------------
(
  SHIP_OWNER=owner SHIP_REPO=repo
  source skills/ship-run/scripts/_lib.sh
  source skills/ship-run/scripts/host/github.sh

  check "github body: the closing line goes above the first heading" \
    "$(printf 'Closes #7\n\n## Summary\n\nit\x27s "quoted" $HOME')" "$(host_pr_create_body "$body" 7 | jq -r .body)"
  printf 'Closes #7\n\n## Summary\n' > "$work/closed.md"
  check "github body: a body already closing the issue is left as written" \
    "$(cat "$work/closed.md")" "$(host_pr_create_body "$work/closed.md" 7 | jq -r .body)"
  check "github body: no issue, no closing line" \
    "$(cat "$body")" "$(host_pr_create_body "$body" "" | jq -r .body)"

  cmd=$(host_pr_create_cmd fix/a-7 main "$title" "$body" 7 | jq -r .command)
  check "github command: the create is the REST POST itself, first on the line" "gh api -X POST" "${cmd:0:14}"
  check "github command: run as printed, gh posts the payload to the pulls route" \
    "$(printf '%s\n' api -X POST repos/owner/repo/pulls --input "$work/body.json" --jq .html_url)" \
    "$(argv "$cmd")"
  check "github command: the payload carries head, base, title, the body and draft false" \
    "$(jq -nc --arg t "$title" --arg b "$(cat "$body")" '{head: "fix/a-7", base: "main", title: $t, body: $b, draft: false}')" \
    "$(jq -c . "$work/body.json")"

  printf 'HTTP/2.0 200 OK\r\n\r\n{"number":5,"html_url":"u","title":"t","body":"","head":{"sha":"s","ref":"h"},"base":{"ref":"main"},"draft":false,"state":"open","merged":false,"mergeable":true,"mergeable_state":"clean","created_at":"2026-11-15T10:00:00Z"}\n' > "$work/pr.http"
  cat > "$work/gh" <<'FAKE'
#!/usr/bin/env bash
cat "$(dirname "$0")/pr.http"
FAKE
  check "github host_pr_get: carries created_at" "2026-11-15T10:00:00Z" \
    "$(PATH=$work:$PATH host_pr_get 5 | jq -r .created_at)"
  finish
) || _failed=1

# --- Azure DevOps --------------------------------------------------------------
cat > "$work/az" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGV_LOG"
FAKE
(
  SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
  source skills/ship-run/scripts/_lib.sh
  source skills/ship-run/scripts/host/ado.sh

  check "ado body: unchanged, the work item links the PR instead" \
    "$(cat "$body")" "$(host_pr_create_body "$body" 7 | jq -r .body)"

  cmd=$(host_pr_create_cmd fix/a-7 main "$title" "$body" 7 | jq -r .command)
  check "ado command: the create is az repos pr create itself, first on the line" "az repos pr create" "${cmd:0:18}"
  check "ado command: run as printed, az gets the old adapter's fields, the description as @<file>" \
    "$(printf '%s\n' repos pr create --org https://dev.azure.com/org --project proj --repository repo \
        --source-branch fix/a-7 --target-branch main --title "$title" --description "@$body" \
        --draft false --work-items 7)" \
    "$(argv "$cmd")"
  check "ado command: no command substitution, which a permission check may refuse" "" \
    "$(grep -F '$(' <<<"$cmd")"
  cmd=$(host_pr_create_cmd fix/a main "$title" "$body" "" | jq -r .command)
  check "ado command: no issue, no work item" "" "$(argv "$cmd" | grep -x -- --work-items)"

  azx() { printf '%s\n' '{"pullRequestId": 5, "title": "t", "description": "", "status": "active",
    "lastMergeSourceCommit": {"commitId": "s"}, "sourceRefName": "refs/heads/h", "targetRefName": "refs/heads/main",
    "isDraft": false, "mergeStatus": "succeeded", "creationDate": "2026-11-15T10:00:00.123Z"}'; }
  check "ado host_pr_get: carries created_at, folded to UTC seconds" "2026-11-15T10:00:00Z" \
    "$(host_pr_get 5 | jq -r .created_at)"
  finish
) || _failed=1

finish
