#!/usr/bin/env bash
# The creative-video turn row against this repo's real configuration. Turn-row
# globs match a file's basename and `owner()` reports `new-root` for a file a
# row's globs match under no row's prefix, so a bare `*.json` in the row made
# every JSON file in the repo a new root (#1026). The row names the skill's
# manifests instead, as the explainer-video row does.
# A stub `node` stands in, so the creative-video suite the row runs costs nothing.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$fixture/node"
chmod +x "$fixture/node"
turn() { PATH="$fixture:$PATH" scripts/check.sh turn "$@" 2>&1 | tail -n 1; }

for f in skills-lock.json .claude/settings.json skills/explainer-video/narrators.json \
  tests/host-fake/defaults/host_pr_get.json skills/setup-harness/templates/settings-hooks.json; do
  check "$f is no new root" '{"rung":"turn","verdict":"skipped","checks":{"turn":"skipped"}}' "$(turn "$f")"
done

check "the skill's package.json runs the creative-video suite" \
  '{"rung":"turn","verdict":"pass","checks":{"tests:creative-video":"pass"}}' \
  "$(turn skills/creative-video/package.json)"

check "a .mjs file under no row's prefix is still a new root" \
  '{"rung":"turn","verdict":"unavailable","checks":{"new-root":"unavailable"}}' \
  "$(turn zz-new-root.mjs)"

finish
