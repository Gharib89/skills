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

# sa_default_ledger: the ledger in the super agent's state directory.
sa_default_ledger() {
  printf '%s/ledger.json' "${SUPER_AGENT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/super-agent}"
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
  doc=$(cat "$1")
}

# sa_write <ledger> <json>: a temp file beside the ledger, then a rename, so a
# reader sees the old ledger or the new one and a crash leaves the old one whole.
sa_write() {
  local dir tmp
  dir=$(dirname "$1")
  mkdir -p "$dir" || sa_tooling "cannot create $dir"
  tmp=$(mktemp "$dir/.ledger.XXXXXX") || sa_tooling "cannot write in $dir"
  if printf '%s\n' "$2" | jq . > "$tmp" && mv "$tmp" "$1"; then return 0; fi
  rm -f "$tmp"
  sa_tooling "cannot write $1"
}
