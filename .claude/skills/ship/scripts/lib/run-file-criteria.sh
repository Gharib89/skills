#!/usr/bin/env bash
# Run-file mechanic: reading an issue's criteria. Sourced by ../run-file.sh, never run.
# shellcheck disable=SC2154 # shares the globals of run-file.sh (SHIP_SCRIPTS)

# The unfenced checkbox lines of an issue's text as `- <n>: <text>` entries: what
# `init --criteria` records under `## Criteria`, and what the gate counts when
# none was recorded. Text with no checkbox gives its top-level list lines under
# a heading naming criteria instead, up to the next heading at its level or
# above, since issues here often state criteria as plain bullets (#958).
criteria_entries() { # criteria_entries <text>
  ship_unfenced "$1" | awk '
    match($0, /^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]+\[[ xX]\][[:space:]]+/) {
      t = substr($0, RLENGTH + 1); sub(/[[:space:]]+$/, "", t)
      if (t != "") box[++nb] = t
      next }
    match($0, /^#+[[:space:]]/) {
      if (level && RLENGTH - 1 <= level) level = 0
      if (!level && tolower($0) ~ /criteria/) level = RLENGTH - 1
      next }
    level && match($0, /^([-*+]|[0-9]+[.)])[[:space:]]+/) {
      t = substr($0, RLENGTH + 1); sub(/[[:space:]]+$/, "", t)
      if (t != "") plain[++np] = t }
    END {
      if (nb) for (i = 1; i <= nb; i++) printf "- %d: %s\n", i, box[i]
      else for (i = 1; i <= np; i++) printf "- %d: %s\n", i, plain[i] }'
}

# How many criteria issue <n>'s body carries, by the rule above; fails where the issue cannot be read.
issue_checkboxes() { # issue_checkboxes <n>
  local body
  body=$("$SHIP_SCRIPTS/read-issue.sh" "$1" 2>/dev/null | jq -er '.body // ""') || return 1
  criteria_entries "$body" | awk 'END { print NR }'
}
