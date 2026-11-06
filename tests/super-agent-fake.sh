# Fake `t3`, `gh` and process tools for super-agent's tests: they answer from
# files under $SA_FAKE and record every call. Sourced, never run.
#
#   bin=$(mktemp -d); source tests/super-agent-fake.sh; sa_fake_install "$bin"
#   export PATH="$bin:$PATH" SA_FAKE=<state dir>
#   sa_thread t-1 running 1 0 /wt/one feat/one-5
#   sa_pr Gharib89/skills feat/one-5 open
#
# `t3 thread show <id> --json` answers `{thread, messages}` from
# `threads/<id>.json`, after the multi-line migration warning the real CLI
# prints on STDOUT (measured on 2026-11-06, so a script has to pick out the
# JSON line); no file is a thread the server does not know: exit 1.
# `SA_T3_RC` makes a found thread exit nonzero after its answer. `gh api
# <endpoint>` answers from `gh/<endpoint with every character outside
# [A-Za-z0-9._-] turned into _>`; no file is a 404, exit 1 with the JSON body
# on stdout like the real CLI (measured 2026-11-06). `pgrep` and `ps` record
# themselves in `proc-calls` and print nothing: a script that matches a
# process by name shows up there. Every t3 and gh call is a line of `calls`.

sa_fake_install() { # <dir>
  cat > "$1/t3" <<'FAKE'
#!/usr/bin/env bash
printf 't3 %s\n' "$*" >> "$SA_FAKE/calls"
[ "$1 $2" = "thread show" ] || { echo "fake t3: unsupported: $*" >&2; exit 2; }
id=$3
printf '%s\n' '[09:53:24.008] WARN (#20): Database migration history diverges from this build. {' \
  "  divergent: [" "    '77:Repair (unknown to this build)'" "  ]" "}"
f="$SA_FAKE/threads/$id.json"
[ -f "$f" ] || { echo "thread $id not found" >&2; exit 1; }
cat "$f"
exit "${SA_T3_RC:-0}"
FAKE
  cat > "$1/gh" <<'FAKE'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$SA_FAKE/calls"
[ "$1" = api ] || { echo "fake gh: unsupported: $*" >&2; exit 2; }
f="$SA_FAKE/gh/$(printf '%s' "$2" | sed 's/[^A-Za-z0-9._-]/_/g')"
[ -f "$f" ] || { printf '%s' '{"message":"Not Found","status":"404"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
cat "$f"
FAKE
  for p in pgrep ps; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "$SA_FAKE/proc-calls"\n' "$p" > "$1/$p"
  done
  chmod +x "$1/t3" "$1/gh" "$1/pgrep" "$1/ps"
  mkdir -p "$SA_FAKE/threads" "$SA_FAKE/gh"
}

# sa_thread <id> <status> <runCount> <pending> <worktree> <branch> [<last message>]
sa_thread() {
  jq -cn --arg id "$1" --arg s "$2" --argjson n "$3" --argjson p "$4" --arg w "$5" \
    --arg b "$6" --arg m "${7:-}" \
    '{thread: {threadId: $id, status: $s, runCount: $n, pendingRequestCount: $p,
       worktreePath: $w, branch: $b, pullRequests: [], settled: false},
      messages: (if $m == "" then [] else [{role: "assistant", runId: "r", text: $m}] end)}' \
    > "$SA_FAKE/threads/$1.json"
}

sa_route() { # <endpoint> <json>: what `gh api <endpoint>` answers
  printf '%s\n' "$2" > "$SA_FAKE/gh/$(printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g')"
}

# sa_pr <owner/name> <branch> <open|merged|closed|none>: the PR list for a branch
sa_pr() {
  local repo=$1 branch=$2 state=$3 body
  case $state in
    open) body='[{"number":7,"state":"open","merged_at":null}]' ;;
    merged) body='[{"number":7,"state":"closed","merged_at":"2026-11-06T10:00:00Z"}]' ;;
    closed) body='[{"number":7,"state":"closed","merged_at":null}]' ;;
    none) body='[]' ;;
  esac
  sa_route "repos/$repo/pulls?head=${repo%%/*}:$(jq -rn --arg s "$branch" '$s | @uri')&state=all&sort=created&direction=desc&per_page=1" "$body"
}

sa_issue() { # <owner/name> <number> <open|closed>
  sa_route "repos/$1/issues/$2" "{\"number\":$2,\"state\":\"$3\"}"
}
