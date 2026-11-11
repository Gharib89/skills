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

# sa_env_words <driver> <env json>: the words `env` takes to run one provider's
# quota and auth commands, into $env_args. A leading `~` in a value is HOME, since
# nothing else expands it and `claude` reads a literal `~/x` as a directory that
# does not exist. A Claude provider with no CLAUDE_CONFIG_DIR gets it unset, so it
# reads the default account and not the caller's; other drivers keep the caller's
# environment. NUL-separated, so a value holding a newline stays one word and
# never becomes the program `env` runs.
sa_env_words() {
  env_args=()
  while IFS= read -r -d '' w; do env_args+=("$w"); done < <(jq -j --arg h "${HOME:-}" --arg d "$1" '
    (. // {}) as $e
    | (if $d == "claude" and ($e | has("CLAUDE_CONFIG_DIR") | not) then "-u\u0000CLAUDE_CONFIG_DIR\u0000" else empty end),
      ($e | to_entries[] | "\(.key)=\(.value)" | sub("^(?<k>[^=]*)=~(?<r>/.*)?$"; "\(.k)=\($h)\(.r // "")")
        | select(explode | any(. == 0) | not) | . + "\u0000")' <<<"$2")
}

# sa_epoch: `SA_NOW` as a JSON number, null when unset or not a whole number, so
# a bad test clock reads as the real one.
sa_epoch() { case ${SA_NOW:-} in ''|*[!0-9]*) printf null ;; *) printf '%s' "$SA_NOW" ;; esac; }

# sa_flag_value <usage> <value>: a flag's value may be neither empty nor dash-led,
# or the next flag is read as the value.
sa_flag_value() { case $2 in -*|'') sa_tooling "$1" ;; esac; }

command -v jq >/dev/null || { printf '{"error":"jq not installed"}\n'; exit 2; }

# The stages an entry moves through, only ever by `reconcile`: `launched` is an
# entry nothing has observed yet; `merged` is a PR merged whose thread is still
# running, watched until it rests; `settled` and `closed` end an entry and are
# never watched again, except a settled `triage` entry, which `reconcile` re-reads
# for a new run (`woke`).

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

# Seconds a thread may rest with no new run before the rest is a stall.
# shellcheck disable=SC2034  # read by watch.sh and reconcile.sh
sa_stall_window=900

# sa_window_flag <usage> <value>: --stall-window, seconds a thread may rest with
# no new run before the rest is a stall; a positive integer.
sa_window_flag() { case $2 in ''|0|*[!0-9]*) sa_tooling "$1" ;; esac; }

# The filter every script shares for an entry still being followed.
# shellcheck disable=SC2034  # read by the scripts that source this file
sa_jq_open='def is_open: .stage != "settled" and .stage != "closed";'

# The one normaliser of each kind, as jq defs a script prepends to its filter.
# `norm_repo` is for an `owner/name` and for a ledger key `owner/name#n`: the host
# treats owner and name as case-insensitive, and the number has no case. `norm_path`
# drops a leading `./` and trailing slashes, so `./skills/ship/` is `skills/ship`.
# Compare the normal form on both sides; store and print the spelling as given.
# shellcheck disable=SC2034  # read by the scripts that source this file
sa_jq_norm='def norm_repo: ascii_downcase; def norm_path: sub("^(\\./)+"; "") | sub("/+$"; "");'

# The waiting list in the owner's order: rows with an `order` first, lowest
# first, then the rest by `since`. `sort_by` is stable, so rows that tie keep the
# order they were written in. Applied to the ledger: `waiting_list`.
# shellcheck disable=SC2034  # read by ledger.sh, reconcile.sh and status.sh
sa_jq_waiting='def waiting_list: (.waiting // []) | sort_by([(.order // 1e18), .since]);'

# sa_key <ledger json> <key>: the key the ledger stores for <key>, whatever its
# case, else <key> itself.
sa_key() { jq -r --arg k "$2" "$sa_jq_norm"'(first(.entries | keys[] | select(norm_repo == ($k | norm_repo))) // $k)' <<<"$1"; }

# `--remote <environment id>=<dir>`, repeatable: where the super agent saved its
# reads of the threads on that linked machine, one `<thread id>.json` each. `t3
# thread show` has no environment flag (measured 2026-11-06), so a remote entry
# is read from these files, which the super agent writes with `t3_thread_read`.
sa_remote_dirs='{}'
# sa_remote_flag <usage> <value>: one `--remote` value into $sa_remote_dirs.
sa_remote_flag() {
  case $2 in ?*=?*) ;; *) sa_tooling "$1" ;; esac
  sa_remote_dirs=$(jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '.[$k] = $v' <<<"$sa_remote_dirs")
}

# sa_observe <entry>: one look at an entry's thread (through the `t3` CLI, or for
# an entry with an `environment_id` through its reply file) and
# its PR (through `gh` REST) as a snapshot in $obs:
# {status, run_count, pending, gate, pr: {number, state}}, `state` one of none,
# open, merged, closed, and `gate` true when the thread's last assistant message
# is a ship merge-gate summary, which carries `ship <version>` as a word of its own and its `Unmet criteria` item (ship
# prints the version in its first reply too, so the version alone is no summary). A thread is found by the id and worktree path the entry holds,
# never by a process name, which once matched the wrong process. On failure it
# returns 1 with $obs_kind (thread-unreadable, thread-mismatch, pr-unreadable)
# and $obs_detail, a JSON object. `t3` prints its migration warning on stdout,
# so the answer is the one line that opens a JSON object.
# With `sa_thread_only` set it stops after the thread read: $obs is then only
# {status, run_count, pending}, and the PR is not looked up.
# shellcheck disable=SC2034  # obs, obs_kind and obs_detail are read by the callers
sa_observe() {
  local thread worktree raw line found env dir reason file
  thread=$(jq -r .thread <<<"$1") worktree=$(jq -r '.worktree // ""' <<<"$1")
  obs_detail=$(jq -cn --arg t "$thread" '{thread: $t}')
  env=$(jq -r '.environment_id // empty' <<<"$1") reason='' file=''
  if [ -n "$env" ]; then
    dir=$(jq -r --arg e "$env" '.[$e] // empty' <<<"$sa_remote_dirs")
    # a thread id with a `/` would name a file outside the reply directory
    case $thread in */*) dir='' ;; esac
    if [ -z "$dir" ]; then reason=no-remote
    else
      file=$dir/$thread.json
      if [ ! -f "$file" ]; then reason=missing
      else
        line=$(jq -c . "$file" 2>/dev/null </dev/null | tail -1)
        [ -n "$line" ] || reason=not-json
      fi
    fi
  else
    raw=$(t3 thread show "$thread" --json --messages 1 2>/dev/null </dev/null) || { obs_kind='thread-unreadable'; return 1; }
    line=$(grep '^{"' <<<"$raw" | tail -1)
  fi
  if [ -z "$reason" ] && ! jq -e '.thread | (.threadId | type) == "string" and (.status | type) == "string"
      and (.runCount | type) == "number" and (.pendingRequestCount | type) == "number"' \
      <<<"$line" >/dev/null 2>&1; then reason=shape; fi
  if [ -n "$reason" ]; then
    obs_kind='thread-unreadable'
    # a remote read names why and which file, so a missing --remote reads apart from a wrong-shaped save
    [ -z "$env" ] || obs_detail=$(jq -cn --arg t "$thread" --arg e "$env" --arg r "$reason" --arg f "$file" \
      '{thread: $t, environment_id: $e, reason: $r} + (if $f == "" then {} else {file: $f} end)')
    return 1
  fi
  found=$(jq -c '{thread: .thread.threadId, worktree: .thread.worktreePath}' <<<"$line")
  want=$(jq -cn --arg t "$thread" --arg w "$worktree" '{thread: $t, worktree: $w}')
  # a `task` entry may hold no worktree: the thread id alone is matched
  [ -n "$worktree" ] || { found=$(jq -c '{thread}' <<<"$found"); want=$(jq -cn --arg t "$thread" '{thread: $t}'); }
  if [ "$found" != "$want" ]; then
    obs_kind='thread-mismatch' obs_detail=$found; return 1
  fi
  # `sa_thread_only` set: the caller wants the thread alone, no PR read.
  if [ -n "${sa_thread_only:-}" ]; then
    obs=$(jq -c '{status: .thread.status, run_count: .thread.runCount, pending: .thread.pendingRequestCount}' <<<"$line"); return 0
  fi
  sa_pr_of "$1" || return 1
  obs=$(jq -c --argjson pr "$pr_obs" '{status: .thread.status, run_count: .thread.runCount,
    pending: .thread.pendingRequestCount,
    gate: ([.messages[]? | select(.role == "assistant")] | last | (.text // "") | (test("(^|[^A-Za-z])ship [0-9]+[.][0-9]+[.][0-9]+") and test("Unmet criteria"))),
    pr: $pr}' <<<"$line")
}

# sa_pr_of <entry>: the entry's PR, found by its branch through `gh` REST, as
# {number, state} in $pr_obs, `state` one of none, open, merged, closed. An entry
# with no repo or no branch (a `task` entry) has no PR: state none. A remote entry
# (an `environment_id`) also carries `checks` for its head commit, `none` (no check
# run yet), `pending` or `done`, since `watch` wakes a remote entry on GitHub alone.
# On failure it returns 1 with $obs_kind `pr-unreadable` and $obs_detail.
# shellcheck disable=SC2034  # pr_obs, obs_kind and obs_detail are read by the callers
sa_pr_of() {
  local repo branch list pr sha runs checks
  repo=$(jq -r '.repo // ""' <<<"$1") branch=$(jq -r '.branch // ""' <<<"$1")
  if [ -z "$repo" ] || [ -z "$branch" ]; then pr_obs='{"number":null,"state":"none"}'; return 0; fi
  # A one-off failed read, with the next one fine, was measured on 2026-11-06,
  # so the read is tried twice before the PR is called unreadable.
  for _ in 1 2; do
    list=$(gh api "repos/$repo/pulls?head=${repo%%/*}:$(sa_uri "$branch")&state=all&sort=created&direction=desc&per_page=1" 2>/dev/null </dev/null) \
      || list=''
    jq -e 'type == "array"' <<<"$list" >/dev/null 2>&1 && break
    sleep 1
  done
  if ! jq -e 'type == "array"' <<<"$list" >/dev/null 2>&1; then
    obs_kind='pr-unreadable' obs_detail=$(jq -cn --arg r "$repo" --arg b "$branch" '{repo: $r, branch: $b}'); return 1
  fi
  pr=$(jq -c '.[0] // null' <<<"$list")
  pr_obs=$(jq -cn --argjson pr "$pr" 'if $pr == null then {number: null, state: "none"}
    else {number: $pr.number, state: (if $pr.merged_at != null then "merged"
      elif $pr.state == "closed" then "closed" else "open" end)} end')
  [ -n "$(jq -r '.environment_id // empty' <<<"$1")" ] || return 0
  checks=none
  sha=$(jq -r '.head.sha // empty' <<<"$pr")
  if [ "$(jq -r .state <<<"$pr_obs")" = open ] && [ -n "$sha" ]; then
    runs=$(gh api "repos/$repo/commits/$sha/check-runs?per_page=100" 2>/dev/null </dev/null) || runs=''
    if ! jq -e '(.check_runs | type) == "array"' <<<"$runs" >/dev/null 2>&1; then
      obs_kind='pr-unreadable' obs_detail=$(jq -cn --arg r "$repo" --arg s "$sha" '{repo: $r, checks_of: $s}'); return 1
    fi
    checks=$(jq -r 'if (.check_runs | length) == 0 then "none" elif any(.check_runs[]; .status != "completed") then "pending" else "done" end' <<<"$runs")
  fi
  pr_obs=$(jq -c --arg c "$checks" --arg h "$sha" '. + {checks: $c, head: $h}' <<<"$pr_obs")
}
