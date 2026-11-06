# What super-agent's scripts share, sourced by each: the JSON answers and
# --help text of Ship's mechanics contract, the ledger's reads and atomic
# writes, and one observation of a supervised thread and its PR. Self-contained,
# because the skill composes no other skill and may be installed alone.

# sa_tooling <message>: a malformed call or a missing tool, exit 2.
sa_tooling() { jq -cn --arg e "$1" '{error: $e}'; printf '%s\n' "$1" >&2; exit 2; }

# sa_fail <message>: the script's own not-ok answer, exit 1.
sa_fail() { jq -cn --arg e "$1" '{error: $e}'; printf '%s\n' "$1" >&2; exit 1; }

# sa_help <usage> "$@": on --help, the usage line then the calling script's
# header from its `# stdout:` line to its `# exit:` line, exit 0.
sa_help() {
  local usage=$1; shift
  [ "${1:-}" = --help ] || return 0
  printf '%s\n' "$usage"
  awk '/^# stdout:/ { f = 1 }
    f { if ($0 !~ /^#/ || /^# exit:/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[1]}"
  exit 0
}

# sa_flag_value <usage> <value>: a flag's value may be neither empty nor dash-led,
# or the next flag is read as the value.
sa_flag_value() { case $2 in -*|'') sa_tooling "$1" ;; esac; }

command -v jq >/dev/null || { printf '{"error":"jq not installed"}\n'; exit 2; }

# The stages an entry moves through. `launched` is an entry nothing has observed
# yet; `settled` and `closed` end it and are never watched again.
# shellcheck disable=SC2034  # read by ledger.sh
sa_stages='launched, running, at-rest, settled, closed'

# sa_read <ledger>: the ledger's JSON in $doc, an empty one for a file not yet
# written. A file that is not JSON or has the wrong shape is refused by name,
# since valid JSON of the wrong shape fails at its first use, far from the file.
# It sets a variable rather than printing, so a refusal's JSON reaches stdout
# and not a command substitution.
# shellcheck disable=SC2034  # doc is read by the scripts that call it
sa_read() {
  [ -f "$1" ] || { doc='{"entries":{},"rulings":[]}'; return 0; }
  jq -e . "$1" >/dev/null 2>&1 || sa_tooling "$1: not JSON"
  jq -e '(.entries | type) == "object"' "$1" >/dev/null || sa_tooling "$1: entries must be an object"
  jq -e '(.rulings | type) == "array"' "$1" >/dev/null || sa_tooling "$1: rulings must be an array"
  doc=$(cat "$1")
}

# sa_write <ledger> <json>: a temp file beside the ledger, then a rename, so a
# reader sees the old ledger or the new one and a crash leaves the old one whole.
sa_write() {
  local dir tmp
  dir=$(dirname "$1")
  mkdir -p "$dir" || sa_tooling "cannot create $dir"
  tmp=$(mktemp "$dir/.ledger.XXXXXX") || sa_tooling "cannot write in $dir"
  trap 'rm -f "$tmp"; trap - RETURN' RETURN
  if printf '%s\n' "$2" | jq . > "$tmp" && mv "$tmp" "$1"; then return 0; fi
  rm -f "$tmp"
  sa_tooling "cannot write $1"
}

# sa_uri <text>: URI-encoded, since a `/` in a branch name otherwise addresses
# another resource.
sa_uri() { jq -rn --arg s "$1" '$s | @uri'; }

# The filter every script shares for an entry still being followed.
# shellcheck disable=SC2034  # read by the scripts that source this file
sa_jq_open='def is_open: .stage != "settled" and .stage != "closed";'

# sa_observe <entry>: one look at an entry's thread (through the `t3` CLI) and
# its PR (through `gh` REST) as a snapshot in $obs:
# {status, run_count, pending, pr: {number, state}}, `state` one of none, open,
# merged, closed. A thread is found by the id and worktree path the entry holds,
# never by a process name, which once matched the wrong process. On failure it
# returns 1 with $obs_kind (thread-unreadable, thread-mismatch, pr-unreadable)
# and $obs_detail, a JSON object. `t3` prints its migration warning on stdout,
# so the answer is the one line that opens a JSON object.
# shellcheck disable=SC2034  # obs, obs_kind and obs_detail are read by the callers
sa_observe() {
  local thread worktree repo branch raw line found list pr
  thread=$(jq -r .thread <<<"$1") worktree=$(jq -r .worktree <<<"$1")
  repo=$(jq -r .repo <<<"$1") branch=$(jq -r .branch <<<"$1")
  obs_detail=$(jq -cn --arg t "$thread" '{thread: $t}')
  raw=$(t3 thread show "$thread" --json --messages 0 2>/dev/null </dev/null) || { obs_kind='thread-unreadable'; return 1; }
  line=$(grep '^{"' <<<"$raw" | tail -1)
  if ! jq -e '.thread.threadId' <<<"$line" >/dev/null 2>&1; then obs_kind='thread-unreadable'; return 1; fi
  found=$(jq -c '{thread: .thread.threadId, worktree: .thread.worktreePath}' <<<"$line")
  if [ "$found" != "$(jq -cn --arg t "$thread" --arg w "$worktree" '{thread: $t, worktree: $w}')" ]; then
    obs_kind='thread-mismatch' obs_detail=$found; return 1
  fi
  list=$(gh api "repos/$repo/pulls?head=${repo%%/*}:$(sa_uri "$branch")&state=all&sort=created&direction=desc&per_page=1" 2>/dev/null </dev/null) \
    || list=''
  if ! jq -e 'type == "array"' <<<"$list" >/dev/null 2>&1; then
    obs_kind='pr-unreadable' obs_detail=$(jq -cn --arg r "$repo" --arg b "$branch" '{repo: $r, branch: $b}'); return 1
  fi
  pr=$(jq -c '.[0] // null' <<<"$list")
  obs=$(jq -c --argjson pr "$pr" '{status: .thread.status, run_count: .thread.runCount,
    pending: .thread.pendingRequestCount,
    pr: (if $pr == null then {number: null, state: "none"}
         else {number: $pr.number, state: (if $pr.merged_at != null then "merged"
           elif $pr.state == "closed" then "closed" else "open" end)} end)}' <<<"$line")
}
