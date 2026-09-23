#!/usr/bin/env bash
# The ship profile's `## Cloud lane` `Bootstrap:`: repairs the cloud sandbox
# image before an unattended fire can claim an issue, so scripts/local-gate.sh
# reaches a full verdict there with no manual steps (issue #249). The image has
# neither tool: `shellcheck`'s npx download is refused by the sandbox proxy, and
# without `gitleaks` the required `secrets` gate is `unavailable`. apt is the
# route the proxy passes. Runs in the cloud lane alone, never on a human's
# machine, so it installs without asking.
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
