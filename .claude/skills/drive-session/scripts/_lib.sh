# What drive-session's scripts share, sourced by each: the JSON answers and
# --help text of Ship's mechanics contract, the Herdr guard, one wrapper around
# the `herdr` CLI and the roster's reads and writes. Self-contained, because the
# skill composes no other skill and may be installed alone.

# ds_tooling <message>: a malformed call or a missing tool, exit 2.
ds_tooling() { jq -cn --arg e "$1" '{error: $e}'; printf '%s\n' "$1" >&2; exit 2; }

# ds_fail <message> [<herdr code>]: the script's own not-ok answer, exit 1.
ds_fail() {
  jq -cn --arg e "$1" --arg c "${2:-}" '{error: $e} + (if $c == "" then {} else {code: $c} end)'
  printf '%s\n' "$1" >&2
  exit 1
}

# ds_help <usage> "$@": on --help, the usage line then the calling script's
# header from its `# stdout:` line to its `# exit:` line, exit 0.
ds_help() {
  local usage=$1; shift
  [ "${1:-}" = --help ] || return 0
  printf '%s\n' "$usage"
  awk '/^# stdout:/ { f = 1 }
    f { if ($0 !~ /^#/ || /^# exit:/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[1]}"
  exit 0
}

# ds_flag_value <usage> <value>: a flag's value may be neither empty nor dash-led,
# or the next flag is read as the value.
ds_flag_value() { case $2 in -*|'') ds_tooling "$1" ;; esac; }

# ds_in_herdr: the guard every roster script runs once its call is well formed
# (`frontier` reads GitHub alone and skips it). A supervisor outside Herdr has
# no tab beside it, and its `herdr` would reach whichever session the socket
# names.
ds_in_herdr() {
  [ "${HERDR_ENV:-}" = 1 ] || ds_tooling "drive-session runs inside Herdr only: HERDR_ENV=1 is not set"
  command -v herdr >/dev/null || ds_tooling "herdr not installed"
}

# ds_herdr <arg>...: runs herdr with no stdin, its stdout in $ds_out. On failure
# returns its exit code with Herdr's error code in $ds_code and its message in
# $ds_msg (Herdr prints a server error as JSON on stderr).
# shellcheck disable=SC2034  # ds_out, ds_code and ds_msg are read by the scripts
ds_herdr() {
  local err st
  err=$(mktemp) || ds_tooling "cannot create a temp file"
  trap 'rm -f "$err"; trap - RETURN' RETURN
  ds_out=$(herdr "$@" 2>"$err" </dev/null); st=$?
  ds_code=$(jq -r '.error.code // empty' "$err" 2>/dev/null)
  ds_msg=$(jq -r '.error.message // empty' "$err" 2>/dev/null)
  [ -n "$ds_msg" ] || ds_msg=$(tail -1 "$err")
  return "$st"
}

# ds_prompt <name> <text>: `agent prompt`, waiting until the turn starts or
# opens a dialog. Text that starts no turn (a local slash command, an Enter that
# did not register) leaves the sequence number where it was, so no `watch` would
# report the session: herdr answers `agent_prompt_stalled` after 5 s. Returns 2
# on that or on herdr's own `timeout`, the text having reached the pane, and 1
# on any other refusal, each with ds_herdr's $ds_code and $ds_msg.
ds_prompt() {
  ds_herdr agent prompt "$1" "$2" --wait --until working --until blocked --timeout 8000 && return 0
  case $ds_code in agent_prompt_stalled | timeout) return 2 ;; esac
  return 1
}

# ds_unstall <name>: Enter at a session whose prompt stalled, up to three times
# with a 10 s wait for its turn after each. Every stall in the #819 batch was
# the text sitting in the input box, and an Enter clears it, but on a loaded
# machine (herdr 0.9.5, load average 80, 12 parallel spawns, measured) claude
# drops the first Enter in most spawns, which stays stuck after 30 s until a
# second Enter, and takes up to 12 s to start the turn of an Enter that did
# take. An Enter at an empty input box starts nothing (three of them left a
# finished session's status and sequence number as they were), so the retry
# cannot double-send. Returns 0 once the turn starts or opens a dialog, else
# nonzero: `send-keys` or the wait refused (its code in $ds_code), or three
# waits timed out.
ds_unstall() {
  for _ in 1 2 3; do
    ds_herdr agent send-keys "$1" Enter || return 1
    ds_herdr agent wait "$1" --until working --until blocked --timeout 10000 && return 0
    [ "$ds_code" = timeout ] || return 1
  done
  return 1
}

# ds_agent_fields <what>: the agent in $ds_out's answer, its status in
# $ds_status and its sequence number in $ds_seq. An answer missing either is
# exit 2: a status read as empty would be acknowledged as if it were real.
# shellcheck disable=SC2034  # ds_status and ds_seq are read by the scripts
ds_agent_fields() {
  local v
  v=$(jq -er '.result.agent | select((.agent_status | type) == "string" and (.state_change_seq | type) == "number")
    | "\(.agent_status) \(.state_change_seq)"' <<<"$ds_out" 2>/dev/null) \
    || ds_tooling "$1: unreadable answer from herdr"
  ds_status=${v% *} ds_seq=${v#* }
}

# ds_agent <name>: `agent get` read through ds_agent_fields. Returns 1 when
# Herdr no longer knows the agent: its claude exited or its pane closed (both
# answer `agent_not_found`, measured on herdr 0.9.3). Any other refusal is exit 1.
ds_agent() {
  if ! ds_herdr agent get "$1"; then
    [ "$ds_code" = agent_not_found ] && return 1
    ds_fail "agent get $1: $ds_msg" "$ds_code"
  fi
  ds_agent_fields "agent get $1"
}

# ds_readable <roster>: exit 2 unless the roster parses with a session list.
ds_readable() {
  jq -e '.sessions | type == "array"' "$1" >/dev/null 2>&1 || ds_tooling "cannot read the roster $1"
}

# ds_held <roster> <name>: exit 1 unless the roster holds the session. A script
# acts only on a session the roster holds, so it never touches a pane it did not
# open.
ds_held() {
  ds_readable "$1"
  jq -e --arg n "$2" 'any(.sessions[]; .name == $n)' "$1" >/dev/null || ds_fail "$2 is not in the roster $1"
}

# ds_write <roster> <jq arg>...: rewrites the roster through one jq filter, a
# missing roster read as an empty one, holding the lock <roster>.lock from the
# read to the move, so parallel calls each keep their update. The lock is a file
# Bash creates under noclobber, an O_EXCL open: flock is missing on macOS, and
# uutils' mkdir (Ubuntu's coreutils) lets two racing calls both succeed. An EXIT
# trap frees it if the script is killed while holding it; one held past 10 s is
# a not-ok answer naming it.
ds_write() {
  local r=$1 i=0 st; shift
  until (set -C; : > "$r.lock") 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt 100 ] || ds_fail "the roster $r stays locked: remove $r.lock once no drive-session script runs"
    sleep 0.1
  done
  ds_lock=$r.lock; trap 'rm -f "$ds_lock"' EXIT
  { [ -f "$r" ] || printf '{"sessions":[]}\n' > "$r"; } && jq "$@" "$r" > "$r.tmp" && mv "$r.tmp" "$r"; st=$?
  rm -f "$r.lock"; trap - EXIT
  [ "$st" -eq 0 ] || ds_fail "cannot write the roster $r"
}

# ds_set <roster> <name> <field> <json value>: rewrites one field of one row.
ds_set() { ds_write "$1" --arg n "$2" --arg f "$3" --argjson v "$4" '(.sessions[] | select(.name == $n))[$f] = $v'; }
