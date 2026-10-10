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
  ds_out=$(herdr "$@" 2>"$err" </dev/null); st=$?
  ds_code=$(jq -r '.error.code // empty' "$err" 2>/dev/null)
  ds_msg=$(jq -r '.error.message // empty' "$err" 2>/dev/null)
  [ -n "$ds_msg" ] || ds_msg=$(tail -1 "$err")
  rm -f "$err"
  return "$st"
}

# ds_row <roster> <name>: the session's roster row, or exit 1. A script acts
# only on a session the roster holds, so it never touches a pane it did not open.
ds_row() {
  local row
  row=$(jq -ce --arg n "$2" '.sessions[] | select(.name == $n)' "$1" 2>/dev/null) \
    || ds_fail "$2 is not in the roster $1"
  printf '%s\n' "$row"
}

# ds_set <roster> <name> <field> <json value>: rewrites one field of one row.
ds_set() {
  jq --arg n "$2" --arg f "$3" --argjson v "$4" '(.sessions[] | select(.name == $n))[$f] = $v' "$1" > "$1.tmp" \
    && mv "$1.tmp" "$1" || ds_fail "cannot write the roster $1"
}
