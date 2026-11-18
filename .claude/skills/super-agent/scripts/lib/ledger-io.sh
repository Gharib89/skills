# Reading and writing the ledger, sourced by _lib.sh: sa_read, the bare
# sa_write, and sa_lock and sa_update, the one way a ledger is written;
# sa_pid_runs, which tells a live lock holder from a reused pid; and sa_archive,
# which moves old ended entries out of the ledger.

# sa_pid_runs <pid> <glob>...: the pid is alive and its command line matches one
# of the globs, so a pid reused by another process after a kill or a reboot does
# not pass for a lock's holder. /bin/ps by its full path, which Linux and macOS
# both ship, and which the tests' fake `ps` on PATH does not shadow.
sa_pid_runs() {
  local args g
  args=$(/bin/ps -p "$1" -o args= 2>/dev/null) || return 1
  shift
  # shellcheck disable=SC2053  # each glob matches on purpose
  for g in "$@"; do [[ $args == $g ]] && return 0; done
  return 1
}

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
  # a ruling's date decides its lapse, so one without a readable date is refused here
  jq -e 'all(.rulings[]; (.date | type) == "string"
    and .date == (.date | try (strptime("%Y-%m-%d") | mktime | strftime("%Y-%m-%d")) catch null))' "$1" >/dev/null \
    || sa_tooling "$1: every ruling needs a date that is a calendar day, YYYY-MM-DD"
  doc=$(cat "$1")
}

# sa_write <ledger> <json>: a temp file beside the ledger, then a rename, so a
# reader sees the old ledger or the new one and a crash leaves the old one whole.
# A ledger is written through sa_update only; the fleet and quota files call this.
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

# sa_lock <ledger>: an exclusive lock on the ledger, held until this process
# exits, so a read and the write it leads to are one step no other ledger write
# lands inside. `<ledger>.lock` holds the holder's pid, created with noclobber
# (an exclusive create in bash itself, so it needs no tool beyond the shell) and
# removed on exit by the EXIT trap this sets, so a script that writes the ledger
# sets no EXIT trap of its own. One whose pid is gone, or now runs none of the
# scripts that write a ledger (a pid reused after a kill or a reboot), is a dead
# writer's, taken over under `<ledger>.lock.takeover` so two waiters never both remove it; one
# that reads empty is kept, since its writer may not have written its pid yet. A
# live holder is waited on for 30 s at most (SA_LOCK_TRIES polls of 0.05 s, 600
# unless a test sets fewer). A second call is a no-op.
sa_lock() {
  [ "${sa_locked:-}" = "$1" ] && return 0
  local pid='' try
  case ${SA_LOCK_TRIES:-600} in 0*|*[!0-9]*) sa_tooling "SA_LOCK_TRIES must be a whole number of 1 or more" ;; esac
  mkdir -p "$(dirname "$1")" || sa_tooling "cannot create $(dirname "$1")"
  for ((try = 0; try < ${SA_LOCK_TRIES:-600}; try++)); do
    (set -C; printf '%s\n' "$$" > "$1.lock") 2>/dev/null && { sa_locked=$1; break; }
    pid=$(cat "$1.lock" 2>/dev/null)
    if [ -n "$pid" ] && ! sa_pid_runs "$pid" '*ledger.sh*' '*status.sh*' '*reconcile.sh*' && (set -C; : > "$1.lock.takeover") 2>/dev/null; then
      [ "$(cat "$1.lock" 2>/dev/null)" != "$pid" ] || rm -f "$1.lock"
      rm -f "$1.lock.takeover"; continue
    fi
    sleep 0.05 2>/dev/null
  done
  [ "${sa_locked:-}" = "$1" ] || { [ -e "$1.lock.takeover" ] && sa_tooling "$1.lock is held by pid ${pid:-unknown} and a takeover was cut short; remove $1.lock and $1.lock.takeover if no ledger write runs"; }
  [ "${sa_locked:-}" = "$1" ] || sa_tooling "$1.lock is held by pid ${pid:-unknown}; remove it if no ledger write runs"
  trap '[ "$(cat "$sa_locked.lock" 2>/dev/null)" = "$$" ] && rm -f "$sa_locked.lock"' EXIT
}

# sa_update <ledger> <jq filter> [jq args]...: the one way to write the ledger.
# Under sa_lock it re-reads the ledger, applies the filter to what it holds now
# and writes the result through sa_write, leaving it in $doc. Two writers that
# each wrote back the copy they read would keep only the last one's change.
sa_update() {
  local ledger=$1 filter=$2 new
  shift 2
  sa_lock "$ledger"
  sa_read "$ledger"
  new=$(jq -c "$@" "$filter" <<<"$doc") && [ -n "$new" ] || sa_tooling "cannot update $ledger"
  doc=$new
  sa_write "$ledger" "$doc"
}

# sa_settled_days: how many days after an entry ends (`settled` or `closed`,
# stamped `settled_at`) it stays in the ledger, and how long a settled triage
# thread is still re-read (ADR 0021). `settled_before($cut)`: an entry that
# settled before the epoch `$cut`, by `settled_at`, or `updated_at` for one
# settled before that stamp; one with neither is never old.
sa_settled_days=7
# shellcheck disable=SC2034  # read by reconcile.sh
sa_jq_settled_before='def settled_before($cut): (.settled_at // .updated_at) as $at | $at != null and ($at | fromdateiso8601) < $cut;'

# sa_archive <ledger> <now epoch>: under the lock, each entry settled or closed
# more than sa_settled_days ago with no cleanup or criteria check owed is appended, whole,
# to `<ledger>.archive.jsonl` and dropped from the ledger, so a wake reads only
# what the super agent may still act on. The append comes first: a crash between
# the two leaves the entry in both, never in neither. Leaves the ledger in $doc.
sa_archive() {
  local ledger=$1 gone
  sa_lock "$ledger"
  sa_read "$ledger"
  gone=$(jq -c --argjson cut "$(($2 - sa_settled_days * 86400))" "$sa_jq_settled_before"'.entries[]
    | select((.stage == "settled" or .stage == "closed") and .cleanup_owed != true and .verify_owed != true
      and settled_before($cut))' <<<"$doc") || sa_tooling "cannot read $ledger"
  [ -n "$gone" ] || return 0
  printf '%s\n' "$gone" >> "$ledger.archive.jsonl" || sa_tooling "cannot write $ledger.archive.jsonl"
  sa_update "$ledger" 'del(.entries[$k[]])' --argjson k "$(jq -sc 'map(.key)' <<<"$gone")"
}
