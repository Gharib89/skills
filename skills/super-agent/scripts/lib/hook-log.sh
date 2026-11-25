# The hooks' log, sourced by watch-guard.sh and the owner-question hooks before
# `_lib.sh`, since a hook must still leave a line when `jq` is missing.

# sa_hook_log_file <name> "$@": `<name>.jsonl` beside the ledger, the ledger being
# the `--ledger` among the arguments, else the default state directory's.
sa_hook_log_file() {
  local n=$1 l=${XDG_STATE_HOME:-$HOME/.local/state}/super-agent/ledger.json i
  shift
  for ((i = 1; i < $#; i++)); do [ "${!i}" = --ledger ] && l=${*:i+1:1}; done
  printf '%s/%s.jsonl' "$(dirname "$l")" "$n"
}

# sa_hook_log <file> <event> [<why>]: one `{at, event, why}` line, written without
# `jq`; <why> is fixed text, never a quote. A failed write is no failure.
sa_hook_log() {
  local why=''
  [ -z "${3:-}" ] || why=",\"why\":\"$3\""
  { mkdir -p "$(dirname "$1")" && printf '{"at":"%s","event":"%s"%s}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" "$why" >> "$1"; } 2>/dev/null
  return 0
}
