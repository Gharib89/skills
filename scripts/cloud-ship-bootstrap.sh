#!/usr/bin/env bash
# The ship profile's `## Cloud lane` `Bootstrap:` (why: that section of
# docs/agents/ship.md, issue #249). Installs whichever of `shellcheck` and
# `gitleaks` is missing through apt, the route the sandbox proxy passes, so
# scripts/local-gate.sh reaches a full verdict. Only ship's `prepare` runs it,
# in a cloud sandbox or the unattended lane, so it installs without asking;
# with both on PATH it does nothing.
#
#   scripts/cloud-ship-bootstrap.sh
#
# exit: 0 both tools on PATH · non-zero otherwise, which ship reads as
# `bootstrap-failed`
set -euo pipefail

tools=(shellcheck gitleaks)
missing=()
for t in "${tools[@]}"; do command -v "$t" >/dev/null || missing+=("$t"); done
[ ${#missing[@]} -eq 0 ] && exit 0

sudo=(); [ "$(id -u)" -eq 0 ] || sudo=(sudo)
# A fresh image may carry no package lists yet; refresh them once and retry.
"${sudo[@]}" apt-get install -y "${missing[@]}" \
  || { "${sudo[@]}" apt-get update && "${sudo[@]}" apt-get install -y "${missing[@]}"; }
for t in "${missing[@]}"; do command -v "$t" >/dev/null; done
