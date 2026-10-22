#!/usr/bin/env bash
# Run-file mechanic: reading an issue's checkboxes as criteria. Sourced by ../run-file.sh, never run.
# shellcheck disable=SC2154 # shares the globals of run-file.sh (SHIP_SCRIPTS)

# The unfenced checkbox lines of an issue's text as `- <n>: <text>` entries: what
# `init --criteria` records under `## Criteria`, and what the gate counts when
# none was recorded.
criteria_entries() { # criteria_entries <text>
  ship_unfenced "$1" | awk 'match($0, /^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]+\[[ xX]\][[:space:]]+/) {
    t = substr($0, RLENGTH + 1); sub(/[[:space:]]+$/, "", t)
    if (t != "") printf "- %d: %s\n", ++n, t }'
}

# How many checkboxes issue <n>'s body carries; fails where the issue cannot be read.
issue_checkboxes() { # issue_checkboxes <n>
  local body
  body=$("$SHIP_SCRIPTS/read-issue.sh" "$1" 2>/dev/null | jq -er '.body // ""') || return 1
  criteria_entries "$body" | awk 'END { print NR }'
}
