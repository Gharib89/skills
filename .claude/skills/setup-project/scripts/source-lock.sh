#!/usr/bin/env bash
# The source lock: Gharib89/skills' `skills-lock.json` on main, each skill the
# source repo writes (`source: "."`) rewritten to `source: "Gharib89/skills"`
# with the `version` its SKILL.md carries on main. setup-status reads it for the
# chain skills' versions, and the skill for the extras and its own staleness.
# The one script of this skill that reaches a host, and only GitHub's public raw
# files, so it needs no credentials whatever the checkout's host.
#
#   source-lock
#
# stdout: {skills: {<name>: {source, ref?, version?}}}, or one {error}
# exit: 0 printed · 1 a fetch failed, or a fetched file is not a lock or a
#   SKILL.md with a dotted version · 2 usage, curl or jq missing
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: source-lock'
sp_help "$usage" "$@"
[ $# -eq 0 ] || sp_tooling "$usage"
command -v jq >/dev/null || sp_tooling 'jq not installed'
command -v curl >/dev/null || sp_tooling 'curl not installed'

raw=https://raw.githubusercontent.com/Gharib89/skills/main
fetch() { curl -fsSL --connect-timeout 10 --max-time 30 "$raw/$1"; }

lock=$(fetch skills-lock.json) || sp_fail "cannot fetch $raw/skills-lock.json"
names=$(jq -er '.skills | to_entries[] | select(.value.source == ".") | .key' <<<"$lock" 2>/dev/null) \
  || sp_fail "not a lock: $raw/skills-lock.json"
for s in $names; do
  md=$(fetch "skills/$s/SKILL.md") || sp_fail "cannot fetch $raw/skills/$s/SKILL.md"
  v=$(sp_front /dev/stdin version <<<"$md")
  [[ $v =~ ^[0-9]+(\.[0-9]+)*$ ]] || sp_fail "no dotted version in $raw/skills/$s/SKILL.md"
  lock=$(jq --arg k "$s" --arg v "$v" '.skills[$k] = {source: "Gharib89/skills", version: $v}' <<<"$lock")
done
jq -c '{skills}' <<<"$lock"
