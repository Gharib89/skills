#!/usr/bin/env bash
# Replay case (new, script only, #1385): the pinned thread's fresh context floor
# was 65,008 tokens, about 36k of it tool definitions, rules files, skills and MCP
# servers it never used (#1370, #1372). From a fixture first request that lists
# skills and a fixture `claude mcp list`, `setup.sh --write` writes the super agent
# folder's settings with the cut: the five tools and every server but T3 and
# smart-compact denied, the global rules files excluded and every skill but
# super-agent switched off. Red on v0.48.0's scripts, whose settings hold hooks only.
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
smart-compact: node compact.js - \xe2\x9c\x98 Failed to connect'

S --write --name laptop >/dev/null
check "the five tools and every server but T3 and smart-compact are denied" \
  '["Agent","Artifact","ListAgents","ShareOnboardingGuide","Workflow","mcp__claude-in-chrome","mcp__claude_ai_Exa","mcp__plugin_playwright_playwright"]' \
  "$(jq -c '.permissions.deny | sort' "$cut")"
check "the global rules files are excluded, and the global CLAUDE.md is not" \
  "[\"$HOME/.claude/rules/*.md\"]" "$(jq -c .claudeMdExcludes "$cut")"
check "every skill but super-agent is switched off" \
  '{"code-review":"off","eli5:eli5":"off","tdd":"off"}' "$(jq -c '.skillOverrides' "$cut")"
check "the cut is a file of its own, so deleting it keeps the hooks" "3 null" "$(jq '.hooks.PreToolUse | length' "$hc") $(jq -c .permissions "$hc")"

finish
