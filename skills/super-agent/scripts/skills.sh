#!/usr/bin/env bash
# The skills a task launch can name, with their one-line descriptions. The super
# agent folder switches every skill but super-agent off, so the pinned thread's
# own listing no longer shows them; setup saves the listing it read (`skills.json`
# in the folder), and this prints it on demand.
#
#   skills
#
# stdout: one `<name>: <description>` line per skill, sorted by name
# exit: 0 printed · 2 usage, or no listing saved yet (run scripts/setup.sh --write)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }
usage='usage: skills'
sa_help "$usage" "$@"
[ $# -eq 0 ] || sa_tooling "$usage"
f=$(sa_home_skills)
jq -e 'type == "object" and length > 0' "$f" >/dev/null 2>&1 \
  || sa_tooling "$f: no skill listing saved yet: run scripts/setup.sh --write"
jq -r 'to_entries | sort_by(.key)[] | "\(.key): \(.value)"' "$f"
