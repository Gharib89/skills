# What setup-project's scripts share, sourced by each: the JSON answers and
# --help text of Ship's mechanics contract, and the frontmatter read. Self-
# contained, because the skill installs at user scope with no other skill
# beside it.

# sp_tooling <message>: a malformed call or a missing tool, exit 2.
sp_tooling() {
  if command -v jq >/dev/null; then jq -cn --arg e "$1" '{error: $e}'; else printf '{"error": "%s"}\n' "$1"; fi
  printf '%s\n' "$1" >&2
  exit 2
}

# sp_fail <message>: the script's own not-ok answer, exit 1.
sp_fail() { jq -cn --arg e "$1" '{error: $e}'; printf '%s\n' "$1" >&2; exit 1; }

# sp_help <usage> "$@": on --help, the usage line then the calling script's
# header from its `# stdout:` line to its `# exit:` line, exit 0.
sp_help() {
  local usage=$1; shift
  [ "${1:-}" = --help ] || return 0
  printf '%s\n' "$usage"
  awk '/^# stdout:/ { f = 1 }
    f { if ($0 !~ /^#/ || /^# exit:/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[1]}"
  exit 0
}

# sp_front <file> <key>: a frontmatter `metadata` value, the indented `  <key>:`.
sp_front() { awk -v k="  $2:" 'NR>1 && /^---$/{exit} index($0, k) == 1 {sub(/^[^:]*: */, ""); print; exit}' "$1"; }
