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

# sa_now_s: the epoch second now, or `SA_NOW` when it is a whole number, so a test
# takes the clock and pins a window's edge.
sa_now_s() { case ${SA_NOW:-} in ''|*[!0-9]*) date -u +%s ;; *) printf '%s' "$SA_NOW" ;; esac; }

# sa_notify_read <fleet>: the fleet file's `notify` into $notify_cmd (empty when
# the file has none) and $notify_delay (seconds, 600 when unset). A notify that
# is no object holding a non-empty command, or whose delay is not a whole number
# of seconds, is refused by name.
# shellcheck disable=SC2034  # read by wake-timer.sh
sa_notify_read() {
  jq -e '(.notify // null) as $n | $n == null or ($n | type == "object" and (.command | type == "string" and length > 0)
      and ((.delay // 600) | type == "number" and . >= 1 and . == floor))' "$1" >/dev/null 2>&1 \
    || sa_tooling "$1: notify must be an object with a non-empty command and a delay of whole seconds, 1 or more"
  notify_cmd=$(jq -r '.notify.command // ""' "$1") notify_delay=$(jq -r '.notify.delay // 600' "$1")
}

# sa_brief_where: where a rule that was a brief line or a brief-bound ruling
# belongs now, the tail of every refusal that names one.
sa_brief_where() {
  printf '%s' "a rule for how ship runs belongs in the repo's ship profile, one for the super agent's own behaviour or a gate-hold ruling in the ledger as a plain ruling, one for machine-wide behaviour in global rules"
}

# sa_fleet_no_brief <fleet>: refuse a fleet file that still carries a `brief`
# line under a repo or a machine, naming its path. No launch message carries one
# any more, so a line left in the file would be read by nothing.
sa_fleet_no_brief() {
  local found
  found=$(jq -r '[(.repos // {} | objects | to_entries[] | select(.value | objects | has("brief")) | "repos.\(.key).brief"),
    (.machines // {} | objects | to_entries[] | select(.value | objects | has("brief")) | "machines.\(.key).brief")] | first // empty' "$1")
  [ -z "$found" ] || sa_tooling "$1: $found is retired: delete it. $(sa_brief_where)"
}

# sa_flag_value <usage> <value>: a flag's value may be neither empty nor dash-led,
# or the next flag is read as the value.
sa_flag_value() { case $2 in -*|'') sa_tooling "$1" ;; esac; }
# sa_quota_file <file>: refuse a --quota file that is not a `quota` read.
sa_quota_file() { [ -f "$1" ] && jq -e '(.providers | type) == "object"' "$1" >/dev/null 2>&1 || sa_tooling "$1: not a quota read"; }

command -v jq >/dev/null || { printf '{"error":"jq not installed"}\n'; exit 2; }

# The stages an entry moves through, by `reconcile` alone (`ledger add` and
# `rethread` only start one): `launching` has no thread yet; `launched` is an
# entry nothing has observed yet; `merged` is a PR merged whose thread is still
# running, watched until it rests; `settled` and `closed` end an entry and are
# never watched again, except a settled `triage` entry, which `reconcile` re-reads
# for a new run (`woke`).

# Reading and writing the ledger.
source "$(dirname "${BASH_SOURCE[0]}")/lib/ledger-io.sh" || { printf '{"error":"cannot source lib/ledger-io.sh"}\n'; exit 2; }
# A ruling's row and its lapse.
source "$(dirname "${BASH_SOURCE[0]}")/lib/rulings.sh" || { printf '{"error":"cannot source lib/rulings.sh"}\n'; exit 2; }
# A usage-limit stop's reset time.
source "$(dirname "${BASH_SOURCE[0]}")/lib/limit.sh" || { printf '{"error":"cannot source lib/limit.sh"}\n'; exit 2; }

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
# tell_live($now), on a tell's `at`: the owner's tell lets a send through for an hour after it
# was recorded, to the second. The call guard judges with it and `ledger tell` prunes with it,
# so the two agree; a time that does not parse is lapsed.
# shellcheck disable=SC2034  # read by the scripts that source this file
sa_jq_tell='def tell_live($now): (try (sub("[.][0-9]+Z$"; "Z") | fromdateiso8601) catch null) as $s | $s != null and $now - $s <= 3600;'

# The ledger a 0.45.0 super agent wrote marked a thread the owner took `paused`; 0.46.0
# calls it `owner_run`. Every reader gets the one name: `sa_read` applies this, and the
# call guard, which reads the file itself, too. `owner_run_since` is the entry's last update.
# shellcheck disable=SC2034  # read by the scripts that source _lib.sh
sa_jq_migrate='.entries |= map_values(if .paused == true then .owner_run = true | .owner_run_since = (.owner_run_since // .updated_at) | del(.paused) else del(.paused) end)'

# The one normaliser of each kind, as jq defs a script prepends to its filter.
# `norm_repo` is for an `owner/name` and for a ledger key `owner/name#n`: the host
# treats owner and name as case-insensitive, and the number has no case. `norm_path`
# drops a leading `./` and trailing slashes, so `./skills/ship-run/` is `skills/ship-run`.
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

# A linked machine's threads, read over SSH.
source "$(dirname "${BASH_SOURCE[0]}")/lib/remote.sh" || { printf '{"error":"cannot source lib/remote.sh"}\n'; exit 2; }

# The last line a supervised run writes when it ends a turn only to wait on its own
# background work (a check, a CI wait, a subagent): ship's run contract (and, for a
# triage launch, `sa_triage_contract`) asks for it word for word, and `sa_observe` reads it as `waiting`. A rest that ends on it is
# running until the stall window passes, so it raises no `run-finished` and adds no
# stall. Defined once here, where the observation matches it.
sa_waiting_line='Waiting on my own background work.'

# The skills that wait on the owner by design (a grill): `launch --skill` records an entry
# for one as interactive, which never counts as stalled and never settles on its rest.
# shellcheck disable=SC2034  # read by launch.sh, which sources this file
sa_interactive_skills=' grilling grill-me grill-with-artifact grill-with-docs '

# The lowest installed ship a ship launch accepts: `launch.sh` answers `stale_ship` below
# it, so the repo is refreshed first. 0.72.0 is the first release named `ship-run`: an
# older copy is installed as `ship`, which a `/ship-run` launch line cannot reach.
# shellcheck disable=SC2034  # read by launch.sh
sa_min_ship='0.72.0'

source "$(dirname "${BASH_SOURCE[0]}")/lib/skill.sh" || { printf '{"error":"cannot source lib/skill.sh"}\n'; exit 2; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/changing.sh" || { printf '{"error":"cannot source lib/changing.sh"}\n'; exit 2; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/needs.sh" || { printf '{"error":"cannot source lib/needs.sh"}\n'; exit 2; }
source "$(dirname "${BASH_SOURCE[0]}")/lib/home.sh" || { printf '{"error":"cannot source lib/home.sh"}\n'; exit 2; }

# The contract line a triage launch carries (`launch.sh`): the triage skill is upstream,
# so no SKILL.md this repo owns can ask a triage run for the waiting line the way ship's
# does (ADR 0020). Built from `sa_waiting_line`, never a second copy of its text.
# shellcheck disable=SC2034  # read by launch.sh
sa_triage_contract="A turn that ends only to wait on your own background work (a check, a subagent) ends with this line, word for word, as its last line: \`$sa_waiting_line\` Your final message is the triage outcome, never that line."

# The contract line of a one-off task.
source "$(dirname "${BASH_SOURCE[0]}")/lib/task.sh" || { printf '{"error":"cannot source lib/task.sh"}\n'; exit 2; }

# `active($w; $now)` for a snapshot (`$obs`): the thread is running, or at rest on
# the waiting line for less than `$w` seconds (`rest_at`, the thread's last update,
# is when its run ended). `waiting` is true only with a `rest_at` to time it by.
# A thread stopped on a usage limit (`limit_reset`, see `sa_observe`) is active until its reset plus `$w`:
# T3 resumes it by itself at the reset, so a stall before then would nudge a thread about to resume.
# shellcheck disable=SC2034  # read by watch.sh and reconcile.sh
sa_jq_active='def active($w; $now): .status == "running" or (.waiting == true and ($now - .rest_at) < $w)
  or (.limit_reset != null and $now < .limit_reset + $w);'

# `thread_shape` for a `t3 thread show --json` answer: the thread fields `sa_observe`
# needs, with their types.
# shellcheck disable=SC2034  # read by sa_observe and owner-read.sh
sa_jq_thread_shape='def thread_shape: (.thread | type) == "object"
  and (.thread.threadId | type) == "string" and (.thread.status | type) == "string"
  and (.thread.runCount | type) == "number" and (.thread.pendingRequestCount | type) == "number";'

# sa_thread_file_ok <thread id>: a thread id that names a file inside an owner-read
# directory (owner-read.sh), never one with a `/` that would reach outside it.
sa_thread_file_ok() { case $1 in */*) return 1 ;; esac; }

# sa_observe <entry>: one look at an entry's thread (through the `t3` CLI, or for
# an entry with an `environment_id` through the read `sa_remote_read` took, lib/remote.sh) and
# its PR (through `gh` REST) as a snapshot in $obs:
# {status, run_count, pending, gate, waiting, last, rest_at, pr: {number, state}}, `state`
# one of none, open, merged, closed (a merged PR adds its `merged_at`), `last` the last
# non-blank line of the thread's last assistant message, trimmed, `waiting`
# true when that line is `sa_waiting_line`, `rest_at`
# the thread's `updatedAt` as an epoch (null when it has none), `limit_reset` the epoch of the reset a
# limit stop names (absent for any other rest: the last line reads `... limit · resets 6:10pm (Africa/Cairo)`,
# the first such time after `rest_at` in that zone), and `gate` true when the thread's last assistant message
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
  local thread worktree raw line found env reason down=''
  thread=$(jq -r .thread <<<"$1") worktree=$(jq -r '.worktree // ""' <<<"$1")
  obs_detail=$(jq -cn --arg t "$thread" '{thread: $t}')
  env=$(jq -r '.environment_id // empty' <<<"$1") reason=''
  if [ -n "$env" ]; then
    # read by `sa_remote_read`, which the caller ran over its open entries this look
    reason=$(jq -r --arg e "$env" '.[$e].reason // empty' <<<"$sa_remote_down")
    if [ -n "$reason" ]; then
      down=$(jq -c --arg e "$env" '.[$e]' <<<"$sa_remote_down")
    else
      line=$(jq -r --arg t "$thread" '.[$t] // empty' <<<"$sa_remote_lines")
    fi
  else
    raw=$(t3 thread show "$thread" --json --messages 1 2>/dev/null </dev/null) || { obs_kind='thread-unreadable'; return 1; }
    line=$(grep '^{"' <<<"$raw" | tail -1)
  fi
  if [ -z "$reason" ] && ! jq -e "$sa_jq_thread_shape"'thread_shape' <<<"$line" >/dev/null 2>&1; then reason=shape; fi
  if [ -n "$reason" ]; then
    obs_kind='thread-unreadable'
    # a remote read names its machine and why: no ssh string, a failed call, or no thread in the answer
    [ -z "$env" ] || obs_detail=$(jq -cn --arg t "$thread" --arg e "$env" --arg r "$reason" --argjson d "${down:-null}" \
      '{thread: $t, environment_id: $e, reason: $r} + (if $d == null then {} else {machine: $d.machine, ssh: $d.detail} end)')
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
  obs=$(jq -c --argjson pr "$pr_obs" --arg wl "$sa_waiting_line" '
    (.thread.updatedAt | if type == "string" then (sub("[.][0-9]+Z$"; "Z") | try fromdateiso8601 catch null) else null end) as $rest
    | ([.messages[]? | select(.role == "assistant")] | last | (.text // "")) as $text
    | ($text | split("\n") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != "")) | last // "") as $last
    | {status: .thread.status, run_count: .thread.runCount,
       pending: .thread.pendingRequestCount,
       gate: ($text | (test("(^|[^A-Za-z])ship [0-9]+[.][0-9]+[.][0-9]+") and test("Unmet criteria"))),
       waiting: ($rest != null and $last == $wl), last: $last,
       rest_at: $rest, pr: $pr,
       limit: ($last
         | capture("limit\\s*[·.-]\\s*resets\\s+(?<time>[0-9]{1,2}(:[0-9]{2})?\\s*[ap]m)\\s*\\((?<tz>[A-Za-z0-9_/+-]+)\\)\\s*$"; "i") // null)}' <<<"$line")
  sa_limit_reset
}

# sa_pr_of <entry>: the entry's PR, found by its branch through `gh` REST, as
# {number, state} in $pr_obs, `state` one of none, open, merged, closed. An entry
# with no repo or no branch (a `task` entry) has no PR: state none. A remote entry
# (an `environment_id`) also carries `checks` for its head commit, `none` (no check
# run yet), `pending` or `done`, since `watch` wakes a remote entry whose machine it cannot read on GitHub alone.
# On failure it returns 1 with $obs_kind `pr-unreadable` and $obs_detail.
# shellcheck disable=SC2034  # pr_obs, obs_kind and obs_detail are read by the callers
sa_pr_of() {
  local repo branch list pr sha runs checks
  repo=$(jq -r '.repo // ""' <<<"$1") branch=$(jq -r '.branch // ""' <<<"$1")
  if [ -z "$repo" ] || [ -z "$branch" ]; then pr_obs='{"number":null,"state":"none"}'; return 0; fi
  # A one-off failed read, with the next one fine, was measured on 2026-11-06,
  # so the read is tried twice before the PR is called unreadable.
  for _ in 1 2; do
    # paged: per_page=1 sorted newest first: only the branch's latest PR is wanted
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
      elif $pr.state == "closed" then "closed" else "open" end)}
      + (if $pr.merged_at != null then {merged_at: $pr.merged_at} else {} end) end')
  [ -n "$(jq -r '.environment_id // empty' <<<"$1")" ] || return 0
  checks=none
  sha=$(jq -r '.head.sha // empty' <<<"$pr")
  if [ "$(jq -r .state <<<"$pr_obs")" = open ] && [ -n "$sha" ]; then
    runs=$(gh api "repos/$repo/commits/$sha/check-runs?per_page=100" 2>/dev/null </dev/null) || runs=''
    if ! jq -e '(.check_runs | type) == "array" and (.check_runs | length) < 100' <<<"$runs" >/dev/null 2>&1; then
      obs_kind='pr-unreadable' obs_detail=$(jq -cn --arg r "$repo" --arg s "$sha" '{repo: $r, checks_of: $s}'); return 1
    fi
    checks=$(jq -r 'if (.check_runs | length) == 0 then "none" elif any(.check_runs[]; .status != "completed") then "pending" else "done" end' <<<"$runs")
  fi
  pr_obs=$(jq -c --arg c "$checks" --arg h "$sha" '. + {checks: $c, head: $h}' <<<"$pr_obs")
}
