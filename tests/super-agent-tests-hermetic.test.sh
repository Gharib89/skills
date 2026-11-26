#!/usr/bin/env bash
# The setup tests' shared prelude (tests/super-agent-setup-lib.sh) keeps
# `setup.sh --write` off the caller's state folder and user settings (#1415): a
# --write run after sourcing it, under an outer HOME and XDG_STATE_HOME seeded
# with sentinel files, leaves both byte-identical and adds no file. A leak
# rewrote the live super agent folder's hooks to point at the checkout that ran
# the tests.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

outer=$(mktemp -d) || exit 2
trap 'rm -rf "$outer"' EXIT
st=$outer/state/super-agent/home/.claude/settings.local.json us=$outer/home/.claude/settings.json
mkdir -p "$(dirname "$st")" "$(dirname "$us")" "$outer/seed"
echo '{"sentinel": "state"}' > "$st"
echo '{"sentinel": "user"}' > "$us"
cp "$st" "$outer/seed/state"; cp "$us" "$outer/seed/user"

# shellcheck disable=SC2016  # expanded by the inner shell, after the prelude sets them
out=$(HOME=$outer/home XDG_STATE_HOME=$outer/state bash -c '
  source tests/super-agent-setup-lib.sh
  sa_machine laptop 12 32768 ""
  sa_provider claude 0 "$claude_ok"; sa_provider codex 0 "$codex_ok"; sa_provider agy 0 "$agy_ok"
  sa_environments "[]"; sa_github alice
  S --write --name laptop | jq -r --arg t "$tmp" "\"\(.home.written) \(.home.folder | startswith(\$t))\""')
check "the --write run wrote its folder under the prelude's temp dir" "true true" "$out"
check "the outer state folder's settings are untouched" ok "$(cmp -s "$outer/seed/state" "$st" && echo ok)"
check "the outer user settings are untouched" ok "$(cmp -s "$outer/seed/user" "$us" && echo ok)"
check "no file is added under the outer HOME or state folder" 2 "$(find "$outer/home" "$outer/state" -type f | wc -l)"

finish
