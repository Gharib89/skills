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

# `guard_has($e)`: the settings hold the state guard entry `$e` (its command), for
# `guard.sh` and `sa_home` alike.
# shellcheck disable=SC2034  # read by guard.sh
sa_jq_guard_has='def guard_has($e): any((.hooks.PreToolUse // [])[]?; any(.hooks[]?; .command == $e.hooks[0].command));'

# `project_rows`: the project rows of a saved `t3_project_list` answer, or of a bare
# array of rows joined from all its pages.
# shellcheck disable=SC2034  # read by handover.sh
sa_jq_projects='def project_rows: if type == "array" then . else .projects end;'

# sa_guard_stale: {settings, entries, unreadable} for the state guard entries left in
# user settings, where `guard.sh --install` wrote them before the folder existed; null
# when the file is missing or holds none. A file that is no JSON object is
# `unreadable` true, never "none". An entry runs any copy's `super-agent/scripts/guard.sh`.
sa_guard_stale() {
  local f=$HOME/.claude/settings.json
  [ -e "$f" ] || { printf null; return 0; }
  jq -c --arg f "$f" --arg re "(^|[[:space:]/'\"])super-agent/scripts/guard\\.sh['\"]?[[:space:]]*\$" \
    '[(.hooks.PreToolUse // [])[]? | select(any(.hooks[]?; .command | strings | test($re)))]
    | if length == 0 then null else {settings: $f, entries: ., unreadable: false} end' "$f" 2>/dev/null \
    || jq -cn --arg f "$f" '{settings: $f, entries: [], unreadable: true}'
}

# sa_home <write: true|false> [<projects file>]: the folder's JSON in $home,
# {folder, settings, written, guard, stale, project_id, needs}. With write true the
# generated settings are rewritten whole (every hook the super agent owns, today the
# state guard), so a run reproduces the same file and a hand edit there is lost.
# `guard` says whether the file holds this copy's guard entry. The projects file is
# every `projects` row of `t3_project_list` (its answer, or the rows of all its pages
# as one array): `project_id` is the live project whose workspace is the folder, null
# when none is. `needs` holds one `<key>: <action>` line per thing the owner fixes: a
# missing guard entry, a stale or unreadable user-settings entry, a missing project.
# shellcheck disable=SC2034  # home is read by the scripts that call it
sa_home() {
  local dir settings entry written=false has stale pid=null needs='[]'
  dir=$(sa_home_dir) settings=$(sa_home_settings) entry=$(sa_guard_entry)
  # sa_write exits on a failed write, so it runs in a subshell: a failure is a need,
  # its reason left on stderr.
  if [ "$1" = true ] && (sa_write "$settings" "$(jq -cn --argjson e "$entry" '{hooks: {PreToolUse: [$e]}}')") >/dev/null; then written=true; fi
  has=$(jq --argjson e "$entry" "$sa_jq_guard_has"'guard_has($e)' "$settings" 2>/dev/null) || has=false
  [ "$has" = true ] || needs=$(jq -c --arg s "$settings" '. + ["Super agent folder: the state guard\u0027s hook is missing from \($s): run scripts/setup.sh --write, or scripts/guard.sh --install"]' <<<"$needs")
  stale=$(sa_guard_stale)
  [ "$stale" = null ] || needs=$(jq -c --argjson st "$stale" '. + (if $st.unreadable then ["State guard: \($st.settings) is no JSON object, so a stale guard entry there cannot be checked: fix the file"]
    else [$st.entries[] | "State guard: remove its stale entry from \($st.settings): \(tojson)"] end)' <<<"$needs")
  if [ -n "${2:-}" ]; then
    # shellcheck disable=SC2154  # sa_jq_norm is set in _lib.sh, which sources this file
    pid=$(jq -c --arg d "$dir" "$sa_jq_norm$sa_jq_projects"'first(project_rows[] | select((.workspaceRoot // "" | norm_path) == ($d | norm_path)
      and .deletedAt == null and .archivedAt == null) | .id) // null' "$2")
    [ "$pid" != null ] || needs=$(jq -c --arg d "$dir" '. + ["Super agent folder: no T3 project has \($d) as its workspace: create one there once, in full access, and the next handover moves the super agent into it"]' <<<"$needs")
  fi
  home=$(jq -cn --arg d "$dir" --arg s "$settings" --argjson w "$written" --argjson g "$has" --argjson st "$stale" --argjson p "$pid" --argjson n "$needs" \
    '{folder: $d, settings: $s, written: $w, guard: $g, stale: $st, project_id: $p, needs: $n}')
}
