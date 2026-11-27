#!/usr/bin/env bash
# Replay: every pinned thread started at a context floor of 65,008 tokens, about
# 36k of it tool definitions, rules files, skills and MCP servers it never used
# (24 Nov, issues #1370 and #1372; over 6,564 calls in six pinned transcripts the
# only skill invoked was super-agent and no server but T3 and smart-compact was
# called). The incident version is v0.48.0's scripts, whose folder settings hold
# hooks only. The fixture is hand-built: a first request that lists skills and a
# `claude mcp list` answer (tests/super-agent-fake.sh). Fixed: `setup.sh --write`
# writes the folder's `.claude/settings.json` with the cut, the five tools and
# every server but T3 and smart-compact denied, the global rules files excluded
# and every skill but super-agent switched off; the trial's off switch deletes it,
# and a failed read writes no cut and raises a need.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/super-agent-setup-lib.sh
sa_machine laptop 12 32768 ""
sa_provider claude 0 "$claude_ok"; sa_provider codex 0 "$codex_ok"; sa_provider agy 0 "$agy_ok"
sa_environments '[]'; sa_github alice
hc=$XDG_STATE_HOME/super-agent/home/.claude/settings.local.json cut=$XDG_STATE_HOME/super-agent/home/.claude/settings.json

sa_pinned_transcript "$HOME/.claude/projects/p/pinned.jsonl" '["code-review", "eli5:eli5", "super-agent", "tdd"]'
sa_mcp_list $'Checking MCP server health\xe2\x80\xa6\n\nclaude.ai Exa: https://mcp.example/exa - \xe2\x9c\x94 Connected
plugin:playwright:playwright: npx @playwright/mcp@latest - \xe2\x9c\x94 Connected
t3-code: t3 mcp - \xe2\x9c\x94 Connected
claude.ai Slack: https://mcp.example/slack - ! Needs authentication
  indented: not a server - \xe2\x9c\x94 Connected
note: no status here
smart-compact: node compact.js - \xe2\x9c\x98 Failed to connect'

S --write --name laptop >/dev/null
check "the five tools and every server but T3 (an indented or status-less line is none) and smart-compact are denied" \
  '["Agent","Artifact","ListAgents","ShareOnboardingGuide","Workflow","mcp__claude-in-chrome","mcp__claude_ai_Exa","mcp__claude_ai_Slack","mcp__plugin_playwright_playwright"]' \
  "$(jq -c '.permissions.deny | sort' "$cut")"
check "the global rules files are excluded, and the global CLAUDE.md is not" \
  "[\"$HOME/.claude/rules/**\"]" "$(jq -c .claudeMdExcludes "$cut")"
check "every skill but super-agent is switched off" \
  '{"code-review":"off","eli5:eli5":"off","tdd":"off"}' "$(jq -c '.skillOverrides' "$cut")"
check "the cut is a file of its own, so deleting it keeps the hooks" "3 null" "$(jq '.hooks.PreToolUse | length' "$hc") $(jq -c .permissions "$hc")"


H=$XDG_STATE_HOME/super-agent/home
: > "$H/cut-off"
out=$(S --write --name laptop)
check "the off switch: the rewrite deletes the cut and keeps the hooks" "true false 3" \
  "$(jq -r .home.written <<<"$out") $([ -f "$cut" ] && echo true || echo false) $(jq '.hooks.PreToolUse | length' "$hc")"
rm "$H/cut-off"

sa_mcp_list "" 1
out=$(S --write --name laptop 2>/dev/null)
check "a failed claude mcp list writes no cut, and raises a need" "false false 1" \
  "$(jq -r .home.written <<<"$out") $([ -f "$cut" ] && echo true || echo false) $(jq '[.home.needs[] | select(test("cut was not written \\(claude mcp list failed"))] | length' <<<"$out")"
sa_mcp_list $'t3-code: t3 mcp - \xe2\x9c\x94 Connected'
echo '[]' > "$cut"
out=$(S --write --name laptop 2>/dev/null)
check "a cut file that is no JSON object is left as it is, and raises a need" "false [] 1" \
  "$(jq -r .home.written <<<"$out") $(jq -c . "$cut") $(jq '[.home.needs[] | select(test("cut was not written \\(.*settings.json: not a JSON object"))] | length' <<<"$out")"
echo '{}' > "$cut"; echo '[]' > "$H/skills.json"
out=$(S --write --name laptop 2>/dev/null)
check "a skills.json that is no JSON object writes no cut either, and raises a need" "false {} 1" \
  "$(jq -r .home.written <<<"$out") $(jq -c . "$cut") $(jq '[.home.needs[] | select(test("cut was not written \\(.*skills.json: not a JSON object"))] | length' <<<"$out")"
echo '{}' > "$H/skills.json"; rm -f "$cut"
jq -cn '{type: "user", message: {role: "user", content: "Base directory for this skill: /x/.claude/skills/super-agent"}}' \
  > "$HOME/.claude/projects/p/pinned.jsonl"
out=$(S --write --name laptop 2>/dev/null)
check "a transcript that loaded the skill but holds no listing writes no cut, and raises a need" "false false 1" \
  "$(jq -r .home.written <<<"$out") $([ -f "$cut" ] && echo true || echo false) $(jq '[.home.needs[] | select(test("cut was not written \\(.*no skill listing"))] | length' <<<"$out")"

rm -f "$H/.claude/settings.json" "$H/skills.json"
sa_pinned_transcript "$HOME/.claude/projects/p/pinned.jsonl" '["code-review", "super-agent"]'
for bad in "" $'t3-code: t3 mcp - \xe2\x9c\x93 Connected'; do
  sa_mcp_list "$bad"
  out=$(S --write --name laptop 2>/dev/null)
  check "a claude mcp list with no t3-code parsed ($( [ -z "$bad" ] && echo empty || echo 'an unknown status')) writes no cut, and raises a need" "false false 1" \
    "$(jq -r .home.written <<<"$out") $([ -f "$cut" ] && echo true || echo false) $(jq '[.home.needs[] | select(test("no t3-code server parsed"))] | length' <<<"$out")"
done

sa_mcp_list $'t3-code: t3 mcp - \xe2\x9c\x94 Connected'
mv "$HOME/.claude/projects" "$tmp/other-root-projects"; mkdir -p "$tmp/cfg"; mv "$tmp/other-root-projects" "$tmp/cfg/projects"
out=$(CLAUDE_CONFIG_DIR=$tmp/cfg S --write --name laptop 2>/dev/null)
check "the rules excluded are those of the config root the pinned thread runs under" "[\"$tmp/cfg/rules/**\"]" \
  "$(jq -c .claudeMdExcludes "$cut")"

finish
