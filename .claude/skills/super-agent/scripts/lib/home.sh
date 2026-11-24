# The super agent folder, sourced by _lib.sh.

# The super agent folder: the folder the pinned thread runs in, `super-agent/home`
# under $XDG_STATE_HOME, so its generated local settings reach no other session. A
# settings file in a repo checkout would change every session run there.
sa_home_dir() { printf '%s/super-agent/home' "${XDG_STATE_HOME:-$HOME/.local/state}"; }
sa_home_settings() { printf '%s/.claude/settings.local.json' "$(sa_home_dir)"; }

# sa_guard_entry: the state guard's PreToolUse entry for this copy of guard.sh.
sa_guard_entry() {
  jq -cn --arg c "bash '$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/guard.sh'" \
    '{matcher: "Edit|Write|MultiEdit|NotebookEdit|Bash", hooks: [{type: "command", command: $c}]}'
}

# sa_guard_stale: {settings, entries} for the state guard entries left in user
# settings, where `guard.sh --install` wrote them before the folder existed; null
# when there are none or the file cannot be read.
sa_guard_stale() {
  local f=$HOME/.claude/settings.json
  jq -c --arg f "$f" '[(.hooks.PreToolUse // [])[]? | select(any(.hooks[]?; .command | strings | test("super-agent/scripts/guard\\.sh\u0027?$")))]
    | if length == 0 then null else {settings: $f, entries: .} end' "$f" 2>/dev/null || printf null
}

# sa_home <write: true|false> [<projects file>]: the folder's JSON in $home,
# {folder, settings, written, guard, stale, project_id, needs}. With write true the
# generated settings are rewritten whole (every hook the super agent owns, today the
# state guard), so a run reproduces the same file and a hand edit there is lost.
# `guard` says whether the file holds this copy's guard entry. The projects file is
# a saved `t3_project_list` answer: `project_id` is the project whose workspace is
# the folder, null when none is. `needs` holds one `<key>: <action>` line per
# thing the owner fixes: a missing guard entry, a stale user-settings entry, a
# missing project.
# shellcheck disable=SC2034  # home is read by the scripts that call it
sa_home() {
  local dir settings entry written=false cur has stale pid=null needs='[]' tmpf
  dir=$(sa_home_dir) settings=$(sa_home_settings) entry=$(sa_guard_entry)
  if [ "$1" = true ] && mkdir -p "$(dirname "$settings")" 2>/dev/null \
      && tmpf=$(mktemp "$(dirname "$settings")/.settings.XXXXXX" 2>/dev/null); then
    if jq -n --argjson e "$entry" '{hooks: {PreToolUse: [$e]}}' > "$tmpf" && mv "$tmpf" "$settings"; then written=true; else rm -f "$tmpf"; fi
  fi
  cur=$(cat "$settings" 2>/dev/null) || cur='{}'
  has=$(jq --argjson e "$entry" 'any((.hooks.PreToolUse // [])[]?; any(.hooks[]?; .command == $e.hooks[0].command))' <<<"$cur" 2>/dev/null) || has=false
  [ "$has" = true ] || needs=$(jq -c --arg s "$settings" '. + ["Super agent folder: the state guard\u0027s hook is missing from \($s): run scripts/setup.sh --write, or scripts/guard.sh --install"]' <<<"$needs")
  stale=$(sa_guard_stale)
  [ "$stale" = null ] || needs=$(jq -c --argjson st "$stale" '. + [$st.entries[] | "State guard: remove its stale entry from \($st.settings): \(tojson)"]' <<<"$needs")
  if [ -n "${2:-}" ]; then
    pid=$(jq -c --arg d "$dir" 'first((.projects // .)[] | select(.workspaceRoot == $d and .deletedAt == null) | .id) // null' "$2")
    [ "$pid" != null ] || needs=$(jq -c --arg d "$dir" '. + ["Super agent folder: no T3 project has \($d) as its workspace: create one there once, in full access, and the next handover moves the super agent into it"]' <<<"$needs")
  fi
  home=$(jq -cn --arg d "$dir" --arg s "$settings" --argjson w "$written" --argjson g "$has" --argjson st "$stale" --argjson p "$pid" --argjson n "$needs" \
    '{folder: $d, settings: $s, written: $w, guard: $g, stale: $st, project_id: $p, needs: $n}')
}
