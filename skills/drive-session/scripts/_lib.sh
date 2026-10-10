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

# ds_in_herdr: the guard every script runs once its call is well formed. A
# supervisor outside Herdr has no tab beside it, and its `herdr` would reach
# whichever session the socket names.
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

# ds_write <roster> <jq arg>...: rewrites the roster through one jq filter.
ds_write() {
  local r=$1; shift
  jq "$@" "$r" > "$r.tmp" && mv "$r.tmp" "$r" || ds_fail "cannot write the roster $r"
}

# ds_set <roster> <name> <field> <json value>: rewrites one field of one row.
ds_set() { ds_write "$1" --arg n "$2" --arg f "$3" --argjson v "$4" '(.sessions[] | select(.name == $n))[$f] = $v'; }
