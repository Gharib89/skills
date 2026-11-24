#!/usr/bin/env bash
# The PreToolUse hook that keeps the super agent's state files out of hand edits:
# it refuses an Edit, Write, MultiEdit or NotebookEdit of the ledger, the fleet file
# or the quota file, and a Bash command that redirects into one or runs mv, tee,
# rm, truncate, dd or sed -i on one, or cp, install or ln onto one. The refusal names
# the script that updates that file, so a missing override surfaces as a refusal the
# super agent reports, not as a forged input. A file is `ledger.json`, `fleet.json` or
# `quota*.json` directly under a `super-agent/` directory. The hook sees the tool
# call only, so a script's own write through its update entry point is never judged.
# A guard rail, not a sandbox: it matches the path text, so `cd` into the directory
# and a relative name, or a shell variable holding the path, get past it.
#
#   guard                                      (hook mode: the PreToolUse JSON on stdin)
#   guard --install [--settings <file>]        add the hook to a Claude settings file
#   guard --status [--settings <file>]         say whether that file holds it
#
# --settings defaults to the super agent folder's `.claude/settings.local.json`
# (`super-agent/home` under $XDG_STATE_HOME), which `setup.sh --write` and every
# handover generate with this entry, so the hook reaches the pinned thread and no
# other session. `--install` merges one PreToolUse entry and keeps every other key,
# as a temp file then a rename, and adds nothing when the hook is already there.
# `--status` also reports `stale`: the guard entries left in `~/.claude/settings.json`
# by an install from before the folder, each the line to remove there.
#
# contract: bare-run
# stdout: hook mode prints nothing; `--install` {settings, installed, changed, entry};
#         `--status` {settings, installed, entry, stale: {settings, entries} or null}
# exit: 0 allowed, installed or status read · 2 a call refused (the message on stderr),
#       a usage error or a settings file that is not JSON
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: guard [--install | --status] [--settings <file>]'
sa_help "$usage" "$@"

entry=$(sa_guard_entry)

if [ $# -gt 0 ]; then
  mode=${1#--}; shift
  settings=$(sa_home_settings)
  case $mode in install|status) ;; *) sa_tooling "$usage" ;; esac
  if [ "${1:-}" = --settings ]; then sa_flag_value "$usage" "${2:-}"; settings=$2; shift 2; fi
  [ $# -eq 0 ] || sa_tooling "$usage"
  if [ -e "$settings" ]; then cur=$(cat "$settings") || sa_tooling "cannot read $settings"; else cur='{}'; fi
  jq -e 'type == "object"' <<<"$cur" >/dev/null 2>&1 || sa_tooling "$settings is not a JSON object"
  jq -e '(.hooks // {}) | type == "object"' <<<"$cur" >/dev/null || sa_tooling "$settings: .hooks must be an object"
  jq -e '(.hooks.PreToolUse // []) | type == "array"' <<<"$cur" >/dev/null || sa_tooling "$settings: .hooks.PreToolUse must be an array"
  has=$(jq --argjson e "$entry" '[(.hooks.PreToolUse // [])[] | select(.hooks[]?.command == $e.hooks[0].command)] | length > 0' <<<"$cur") \
    || sa_tooling "cannot read the hooks in $settings"
  changed=false
  if [ "$mode" = install ] && [ "$has" = false ]; then
    # cp -p first, so the replacement keeps the file's mode (settings can hold secrets).
    mkdir -p "$(dirname "$settings")" && { [ ! -e "$settings" ] || cp -p "$settings" "$settings.tmp.$$"; } \
      && jq --argjson e "$entry" '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$e])' <<<"$cur" > "$settings.tmp.$$" \
      && mv "$settings.tmp.$$" "$settings" || sa_tooling "cannot write $settings"
    has=true changed=true
  fi
  if [ "$mode" = install ]; then
    jq -cn --arg s "$settings" --argjson i "$has" --argjson c "$changed" --argjson e "$entry" '{settings: $s, installed: $i, changed: $c, entry: $e}'
  else
    jq -cn --arg s "$settings" --argjson i "$has" --argjson e "$entry" --argjson st "$(sa_guard_stale)" '{settings: $s, installed: $i, entry: $e, stale: $st}'
  fi
  exit 0
fi

# Hook mode. A call this cannot read is allowed: the hook refuses a known write, it
# is no gate on every tool.
input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null) || exit 0
state='super-agent/(ledger|fleet|quota[^[:space:]/"'"'"']*)\.json'
refuse() { # <protected file text>
  local how
  case $1 in
    *super-agent/ledger.json*) how='scripts/ledger.sh --ledger <ledger> <subcommand> (pause, unpause, drop, ...; see its --help)' ;;
    *super-agent/fleet.json*) how='scripts/fleet.sh --fleet <fleet> pin|unpin|slots, or scripts/setup.sh --write' ;;
    *) how='scripts/quota.sh --fleet <fleet> --save <file> --wake <id>' ;;
  esac
  printf 'Refused: do not write %s by hand. Use %s. If no flag covers what you need, report the missing override to the owner.\n' "$1" "$how" >&2
  exit 2
}
case $tool in
  Edit|Write|MultiEdit|NotebookEdit)
    path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
    [[ $path =~ (^|/)$state$ ]] && refuse "$path" ;;
  Bash)
    cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
    # A quoted target may hold spaces: `> '/home/a b/.../ledger.json'`. Each quote closes
    # right after the file name, so a quoted `>` earlier in a read is no redirect.
    [[ $cmd =~ \>[\|\>]?[[:space:]]*(\"[^\"]*($state)\"|\'[^\']*($state)\'|[^[:space:]\;\&\|]*($state)) ]] \
      && refuse "${BASH_REMATCH[2]}${BASH_REMATCH[4]}${BASH_REMATCH[6]}"
    # Split into simple commands in bash: a sed `\n` replacement is unspecified in POSIX.
    split=${cmd//&&/$'\n'}; split=${split//||/$'\n'}; split=${split//;/$'\n'}; split=${split//|/$'\n'}
    while IFS= read -r seg; do
      # Judge the command word only, so a script call whose text says `rm` passes.
      while [[ $seg =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|sudo|command)[[:space:]]+(.*)$ ]]; do seg=${BASH_REMATCH[2]}; done
      [[ $seg =~ ^[[:space:]]*(mv|tee|rm|truncate|dd|sed[[:space:]]+-[a-zA-Z]*i|perl[[:space:]]+-[a-zA-Z]*i)([[:space:]]|$) ]] \
        && [[ $seg =~ ($state) ]] && refuse "${BASH_REMATCH[1]}"
      # A copy only writes its last word, so copying the file elsewhere is a read.
      [[ $seg =~ ^[[:space:]]*(cp|install|ln)([[:space:]]|$) ]] \
        && [[ $seg =~ ($state)[\"\']?[[:space:]]*$ ]] && refuse "${BASH_REMATCH[1]}"
    done <<<"$split" ;;
esac
exit 0
