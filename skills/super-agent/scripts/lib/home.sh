# The super agent folder, sourced by _lib.sh.

# The super agent folder: the folder the pinned thread runs in, `super-agent/home`
# under $XDG_STATE_HOME, so its generated local settings reach no other session. A
# settings file in a repo checkout would change every session run there.
sa_home_dir() { printf '%s/super-agent/home' "${XDG_STATE_HOME:-$HOME/.local/state}"; }
sa_home_settings() { printf '%s/.claude/settings.local.json' "$(sa_home_dir)"; }
# The cut lives in a file of its own beside the hooks' file, so deleting it ends
# the context floor trial and keeps the guards ([setup](../../reference/setup.md)).
sa_home_cut_settings() { printf '%s/.claude/settings.json' "$(sa_home_dir)"; }
# The listing the cut was read from, {name: one-line description}, for `skills.sh`.
sa_home_skills() { printf '%s/skills.json' "$(sa_home_dir)"; }
# The trial's off switch: while this file exists, a rewrite deletes the cut's file
# instead of writing it.
sa_home_cut_off() { printf '%s/cut-off' "$(sa_home_dir)"; }

# sa_transcript_roots: one `projects` folder per line, under $CLAUDE_CONFIG_DIR
# and every `~/.claude*`, where Claude Code keeps its transcripts.
sa_transcript_roots() {
  local r
  for r in "${CLAUDE_CONFIG_DIR:-}" "$HOME"/.claude*; do [ -n "$r" ] && [ -d "$r/projects" ] && printf '%s/projects\n' "$r"; done
}
# sa_loaded_skill <transcript>: true when the transcript loaded the super-agent
# skill. A skill load is a user entry that opens on the line; a session that only
# quotes the line, in a command or its output, never loaded the skill.
sa_loaded_skill() {
  grep -qF 'Base directory for this skill: ' "$1" && jq -enR 'first(inputs | fromjson? // empty
    | select(type == "object" and .type == "user" and (.isSidechain | not)) | .message.content
    | if type == "array" then .[]? | .text? else . end | strings
    | select(test("^Base directory for this skill: \\S*/super-agent(\\s|$)"))) | true' "$1" >/dev/null 2>&1
}

# sa_home_cut <cut file>: the cut's settings, which take about 36k tokens off the
# pinned thread's context floor (measured): the five tools it never needs denied,
# the global rules files excluded (the global CLAUDE.md stays), every skill but
# super-agent switched off and every MCP server but T3 and smart-compact denied.
# Skills come from the first request of the newest transcript that loaded this
# skill (built-in and account skills are not on disk), servers from `claude mcp
# list` run in the folder; neither lists `claude-in-chrome`, which is built in.
# Each list keeps what the file already holds: after the cut, the pinned thread's
# own listing names only the skills left on. Also writes the listing to
# `skills.json`. Exits 1, its reason on stderr, when the cut file is no JSON
# object or a read fails (`claude mcp list`, or one naming no t3-code; the
# transcript's listing; `skills.json`). Exits 3, the cut still printed, when it
# switches no skill off: no transcript loaded the skill and none was saved.
sa_home_cut() {
  local prev='{}' listing='{}' saved='{}' t='' f mcp servers rules
  if [ -f "$1" ]; then
    prev=$(jq -ce 'objects' "$1" 2>/dev/null) || { echo "$1: not a JSON object" >&2; return 1; }
  fi
  while IFS= read -r f; do sa_loaded_skill "$f" && { t=$f; break; }; done \
    < <(sa_transcript_roots | while IFS= read -r root; do find "$root" -name '*.jsonl' -not -path '*/subagents/*' -printf '%T@ %p\n' 2>/dev/null; done | sort -rn | cut -d' ' -f2-)
  if [ -n "$t" ]; then
    listing=$(jq -cnR 'first(inputs | fromjson? // empty | select(type == "object" and .type == "attachment"
        and .attachment.type? == "skill_listing") | .attachment) // error("no listing")
      | if (.names | type) == "array" and (.names | length) > 0 and (.content | type) == "string" then . else error("partial") end
      | (.content | split("\n")) as $l
      | [.names[]? | strings as $n | {key: $n, value: (first($l[] | select(startswith("- \($n): ")) | .[($n | length) + 4:]) // "")}]
      | from_entries' "$t" 2>/dev/null) || { echo "$t: no skill listing with names and descriptions" >&2; return 1; }
  fi
  if [ -f "$(sa_home_skills)" ]; then
    saved=$(jq -ce 'objects' "$(sa_home_skills)" 2>/dev/null) || { echo "$(sa_home_skills): not a JSON object" >&2; return 1; }
  fi
  saved=$(jq -cn --argjson s "$saved" --argjson l "$listing" '$s + $l | del(.["super-agent"])')
  (sa_write "$(sa_home_skills)" "$saved") >/dev/null || { echo "cannot write $(sa_home_skills)" >&2; return 1; }
  mcp=$(cd "$(sa_home_dir)" && timeout 60 claude mcp list 2>/dev/null </dev/null) || { echo "claude mcp list failed or timed out in $(sa_home_dir)" >&2; return 1; }
  # The pinned thread always has t3-code, so a parse that misses it read nothing.
  servers=$(jq -cn --arg mcp "$mcp" '[$mcp | split("\n")[] | capture("^(?<n>[^ ].*?): .* - [\u2714\u2718!]").n]')
  jq -e 'index("t3-code")' <<<"$servers" >/dev/null || { echo "claude mcp list: no t3-code server parsed" >&2; return 1; }
  # The rules folder of the config root the pinned thread runs under: the found
  # transcript's, else the default one. `**` reaches subfolders (probed).
  rules=${t%/projects/*}; [ -n "$t" ] || rules=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
  local cut
  cut=$(jq -cn --argjson p "$prev" --argjson s "$saved" --arg rules "$rules/rules/**" --argjson n "$servers" '
    def server: "mcp__" + gsub("[^A-Za-z0-9_-]"; "_");
    ($n - ["t3-code", "smart-compact"] | map(server)) as $servers
    | {permissions: {deny: (["Agent", "Artifact", "ListAgents", "ShareOnboardingGuide", "Workflow", "mcp__claude-in-chrome"]
        + $servers + [$p.permissions.deny[]? | strings] | unique)},
       claudeMdExcludes: ([$rules] + [$p.claudeMdExcludes[]? | strings] | unique),
       skillOverrides: ([($s | keys[]), ($p.skillOverrides // {} | objects | keys[])] - ["super-agent"] | unique
         | map({key: ., value: "off"}) | from_entries)}')
  printf '%s\n' "$cut"
  jq -e '.skillOverrides != {}' <<<"$cut" >/dev/null \
    || { echo "no transcript that loaded the super-agent skill" >&2; return 3; }
}

# sa_shq <text>: the text single-quoted for a shell, each ' in it written '\''.
sa_shq() { local q="'\\''"; printf "'%s'" "${1//\'/$q}"; }

# sa_hook_entry <script> [<matcher> [<suffix>]]: this copy's <script> as a hook entry,
# its command followed by <suffix>.
sa_hook_entry() {
  local p
  p=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/$1
  jq -cn --arg c "bash $(sa_shq "$p")${3:-}" --arg m "${2:-}" \
    '(if $m != "" then {matcher: $m} else {} end) + {hooks: [{type: "command", command: $c}]}'
}
# The state guard's PreToolUse entry and the watch guard's Stop entry.
sa_guard_entry() { sa_hook_entry guard.sh 'Edit|Write|MultiEdit|NotebookEdit|Bash'; }
# The call guard's PreToolUse entry. Its exit 2 is the refusal, so, like the state
# guard's, it is not swallowed: a send into a thread that is not the super agent's
# is what it exists to stop.
sa_call_guard_entry() { sa_hook_entry call-guard.sh 'mcp__t3-code__t3_thread_send|mcp__t3-code__t3_thread_send_attachments|Bash'; }
# A Stop hook's exit 2 blocks the stop, so a usage error in the watch guard is swallowed.
sa_watch_guard_entry() { sa_hook_entry watch-guard.sh '' ' || true'; }
# The owner-question hooks: the question flag (UserPromptSubmit) and the observe hook
# (PreToolUse, every tool). Their exit 2 erases the prompt or refuses the call, so a
# usage error is swallowed too.
sa_question_flag_entry() { sa_hook_entry question-flag.sh '' ' || true'; }
sa_observe_entry() { sa_hook_entry observe.sh '' ' || true'; }

# The wake timer's systemd user units, the owner's to install. `sa_timer_active`:
# true when systemctl reports the timer active, false for any other state (a
# unit never installed reads `inactive`), null when systemctl printed no state
# (no systemctl, no user bus): a failed read is no verdict.
# `sa_timer_units`: {dir, service, timer, enable}, the two unit files' text, the
# folder they go in and the line that enables them. The service carries this
# shell's PATH, since a user unit's own PATH lacks where `t3` usually lives.
sa_timer_active() {
  local s; s=$(systemctl --user is-active super-agent-wake.timer 2>/dev/null)
  case $s in active) echo true ;; '') echo null ;; *) echo false ;; esac
}
sa_timer_units() {
  local p l f
  p=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wake-timer.sh
  # The systemd user manager need not carry this shell's XDG dirs, so the
  # ledger and fleet paths resolved here go on the command line.
  l=${XDG_STATE_HOME:-$HOME/.local/state}/super-agent/ledger.json
  f=${XDG_CONFIG_HOME:-$HOME/.config}/super-agent/fleet.json
  jq -cn --arg d "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" --arg path "$PATH" \
    --arg x "/usr/bin/env bash $(sa_shq "$p") --ledger $(sa_shq "$l") --fleet $(sa_shq "$f")" '{dir: $d,
    service: "[Unit]\nDescription=Super agent wake timer tick\n\n[Service]\nType=oneshot\nEnvironment=\"PATH=\($path)\"\nExecStart=\($x)\n",
    timer: "[Unit]\nDescription=Wake the super agent when its own turn died\n\n[Timer]\nOnBootSec=5min\nOnUnitActiveSec=5min\n\n[Install]\nWantedBy=timers.target\n",
    enable: "systemctl --user daemon-reload && systemctl --user enable --now super-agent-wake.timer"}'
}

# `hook_has($ev; $e)`: the settings hold, under event `$ev`, the entry `$e` (its
# command), for `guard.sh` and `sa_home` alike.
# shellcheck disable=SC2034  # read by guard.sh
sa_jq_hook_has='def hook_has($ev; $e): any((.hooks[$ev] // [])[]?; any(.hooks[]?; .command == $e.hooks[0].command));'

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
  # Slurped, so an empty file or one holding `null` or two values is no object too.
  jq -cs --arg f "$f" --arg re "(^|[[:space:]/'\"])super-agent/scripts/guard\\.sh['\"]?[[:space:]]*\$" \
    'if length != 1 or (.[0] | type) != "object" then error("no object") else .[0] end
    | [(.hooks.PreToolUse // [])[]? | select(any(.hooks[]?; .command | strings | test($re)))]
    | if length == 0 then null else {settings: $f, entries: ., unreadable: false} end' "$f" 2>/dev/null \
    || jq -cn --arg f "$f" '{settings: $f, entries: [], unreadable: true}'
}

# sa_home_write_cut: writes the cut's file, or deletes it while the folder holds
# `cut-off`. Exits 1 when it is not written, with the reason on stderr, and 3
# when it is written but switches no skill off (sa_home_cut's 3).
sa_home_write_cut() {
  local cut cut_file rc=0
  cut_file=$(sa_home_cut_settings)
  if [ -f "$(sa_home_cut_off)" ]; then rm -f "$cut_file"; return; fi
  cut=$(sa_home_cut "$cut_file") || rc=$?
  [ "$rc" = 0 ] || [ "$rc" = 3 ] || return 1
  (sa_write "$cut_file" "$cut") >/dev/null || { echo "cannot write $cut_file" >&2; return 1; }
  return "$rc"
}

# sa_home <write: true|false> [<projects file>]: the folder's JSON in $home,
# {folder, settings, written, guard, call_guard, watch_guard, question_flag, observe, stale,
# project_id, needs}. With write true the generated settings are rewritten whole (every hook
# the super agent owns: the state guard, the call guard, the watch guard, the question flag
# and the observe hook), so a run reproduces the same file and a hand edit there is lost;
# then the cut's file (sa_home_cut; deleted instead while the folder holds `cut-off`),
# and `written` is true only when both were written.
# `guard`, `call_guard`, `watch_guard`, `question_flag` and `observe` say whether the file
# holds this copy's entry for each. The projects file is
# every `projects` row of `t3_project_list` (its answer, or the rows of all its pages
# as one array): `project_id` is the live project whose workspace is the folder, null
# when none is. `needs` holds one `<key>: <action>` line per thing the owner fixes: a
# missing hook entry (any of the five), a wake timer systemctl does not report running, a
# stale or unreadable user-settings entry, a missing project, a cut not written.
# shellcheck disable=SC2034  # home is read by the scripts that call it
sa_home() {
  local dir settings entry wentry qentry oentry centry cut_err cut_rc=0 written=false has whas qhas ohas chas stale pid=null needs='[]'
  dir=$(sa_home_dir) settings=$(sa_home_settings) entry=$(sa_guard_entry) wentry=$(sa_watch_guard_entry)
  qentry=$(sa_question_flag_entry) oentry=$(sa_observe_entry) centry=$(sa_call_guard_entry)
  # The bare write exits on a failure, so it runs in a subshell, its reason left on
  # stderr; a cut not written, or one switching no skill off, is a need.
  if [ "$1" = true ] && (sa_write "$settings" "$(jq -cn --argjson e "$entry" --argjson w "$wentry" --argjson q "$qentry" --argjson o "$oentry" --argjson c "$centry" \
    '{hooks: {PreToolUse: [$e, $o, $c], UserPromptSubmit: [$q], Stop: [$w]}}')") >/dev/null; then
    cut_err=$(sa_home_write_cut 2>&1 >/dev/null) || cut_rc=$?
    case $cut_rc in
      0) written=true ;;
      3) written=true
        needs='["Super agent folder: the context floor cut switches no skill off (no transcript that loaded the super-agent skill): run scripts/setup.sh --write from the pinned thread"]' ;;
      *) needs=$(jq -cn --arg e "$cut_err" '["Super agent folder: the context floor cut was not written (\($e | split("\n") | last)): fix that, then run scripts/setup.sh --write"]') ;;
    esac
  fi
  has=$(jq --argjson e "$entry" "$sa_jq_hook_has"'hook_has("PreToolUse"; $e)' "$settings" 2>/dev/null) || has=false
  whas=$(jq --argjson e "$wentry" "$sa_jq_hook_has"'hook_has("Stop"; $e)' "$settings" 2>/dev/null) || whas=false
  qhas=$(jq --argjson e "$qentry" "$sa_jq_hook_has"'hook_has("UserPromptSubmit"; $e)' "$settings" 2>/dev/null) || qhas=false
  ohas=$(jq --argjson e "$oentry" "$sa_jq_hook_has"'hook_has("PreToolUse"; $e)' "$settings" 2>/dev/null) || ohas=false
  chas=$(jq --argjson e "$centry" "$sa_jq_hook_has"'hook_has("PreToolUse"; $e)' "$settings" 2>/dev/null) || chas=false
  [ "$chas" = true ] || needs=$(jq -c --arg s "$settings" '. + ["Super agent folder: the call guard\u0027s PreToolUse entry is missing from \($s): run scripts/setup.sh --write"]' <<<"$needs")
  [ "$qhas" = true ] || needs=$(jq -c --arg s "$settings" '. + ["Super agent folder: the question flag\u0027s UserPromptSubmit hook is missing from \($s): run scripts/setup.sh --write"]' <<<"$needs")
  [ "$ohas" = true ] || needs=$(jq -c --arg s "$settings" '. + ["Super agent folder: the observe hook\u0027s PreToolUse entry is missing from \($s): run scripts/setup.sh --write"]' <<<"$needs")
  [ "$whas" = true ] || needs=$(jq -c --arg s "$settings" '. + ["Super agent folder: the watch guard\u0027s Stop hook is missing from \($s): run scripts/setup.sh --write"]' <<<"$needs")
  [ "$has" = true ] || needs=$(jq -c --arg s "$settings" '. + ["Super agent folder: the state guard\u0027s hook is missing from \($s): run scripts/setup.sh --write, or scripts/guard.sh --install"]' <<<"$needs")
  case $(sa_timer_active) in
    false) needs=$(jq -c --arg d "$(sa_timer_units | jq -r .dir)" '. + ["Wake timer: super-agent-wake.timer is not running: write the unit files scripts/guard.sh --install prints into \($d), then run the enable line it prints"]' <<<"$needs") ;;
    null) needs=$(jq -c '. + ["Wake timer: systemctl --user cannot be read here (no systemctl or no user bus), so whether super-agent-wake.timer runs is unknown"]' <<<"$needs") ;;
  esac
  stale=$(sa_guard_stale)
  [ "$stale" = null ] || needs=$(jq -c --argjson st "$stale" '. + (if $st.unreadable then ["State guard: \($st.settings) is no JSON object, so a stale guard entry there cannot be checked: fix the file"]
    else [$st.entries[] | "State guard: remove its stale entry from \($st.settings): \(tojson)"] end)' <<<"$needs")
  if [ -n "${2:-}" ]; then
    # shellcheck disable=SC2154  # sa_jq_norm is set in _lib.sh, which sources this file
    pid=$(jq -c --arg d "$dir" "$sa_jq_norm$sa_jq_projects"'first(project_rows[] | select((.workspaceRoot // "" | norm_path) == ($d | norm_path)
      and .deletedAt == null and .archivedAt == null) | .id) // null' "$2") || sa_tooling "$2: a project row cannot be read"
    [ "$pid" != null ] || needs=$(jq -c --arg d "$dir" '. + ["Super agent folder: no T3 project has \($d) as its workspace: create one there once, in full access, and the next handover moves the super agent into it"]' <<<"$needs")
  fi
  home=$(jq -cn --arg d "$dir" --arg s "$settings" --argjson w "$written" --argjson g "$has" --argjson cg "$chas" --argjson wg "$whas" --argjson qf "$qhas" --argjson ob "$ohas" --argjson st "$stale" --argjson p "$pid" --argjson n "$needs" \
    '{folder: $d, settings: $s, written: $w, guard: $g, call_guard: $cg, watch_guard: $wg, question_flag: $qf, observe: $ob, stale: $st, project_id: $p, needs: $n}')
}
