#!/usr/bin/env bash
# skills/setup-skills/cloud-ship-bootstrap.sh: the cloud-lane `Bootstrap:`
# setup-skills writes over a harness. The subject is its order and its exits:
# nothing outside a cloud session; the harness cloud setup at the harness
# profile's `Setup:` path first, a failure there failing the bootstrap, and
# `Setup: None.` skipping it; then the secrets scanner, installed only when
# missing. The cloud setup, the scanner and apt are stubs that log their calls.
# This repo's own scripts/cloud-ship-bootstrap.sh is an installed copy, held to
# the template outside its configuration block.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
bash_bin=$(command -v bash)
d=$fixture/repo bin=$fixture/bin; mkdir -p "$d/scripts" "$d/docs/agents" "$bin"
sed "s|__SCANNER__|fakescan|; s|__SCANNER_INSTALL__|apt_install fakescan|" \
  skills/setup-skills/cloud-ship-bootstrap.sh > "$d/scripts/cloud-ship-bootstrap.sh"
# The stub cloud setup logs its call and exits $SETUP_RC.
printf '#!%s\necho setup >> "$CALLS"\nexit "${SETUP_RC:-0}"\n' "$bash_bin" > "$d/scripts/cloud-setup.sh"
git -C "$d" init -q
# apt-get: logs its arguments; an install fails until an `update` has run, as on
# a fresh image with no package lists, then creates each package as a tool,
# unless $APT_INERT is set; $APT_BROKEN fails every call. sudo passes through.
cat > "$bin/apt-get" <<FAKE
#!$bash_bin
echo "apt-get \$*" >> "\$CALLS"
[ -n "\${APT_BROKEN:-}" ] && exit 100
if [ "\$1" = update ]; then : > "$fixture/updated"; exit 0; fi
[ -e "$fixture/updated" ] || exit 100
[ -n "\${APT_INERT:-}" ] && exit 0
shift 2
for p in "\$@"; do printf '#!/bin/sh\\n' > "$bin/\$p"; chmod +x "$bin/\$p"; done
FAKE
printf '#!%s\nexec "$@"\n' "$bash_bin" > "$bin/sudo"
chmod +x "$bin/apt-get" "$bin/sudo"

# profile <Setup: value>: write the harness profile's `## Cloud` section.
profile() { printf '# Harness profile\n\n## Check entry point\n\nLocation: scripts/check.sh\n\n## Cloud\n\nVerdict: cloud-first\nSetup: %s\n' "$1" > "$d/docs/agents/harness.md"; }
# boot [VAR=value...]: run the bootstrap in a cloud session; sets rc and calls.
boot() {
  : > "$fixture/calls"; rm -f "$fixture/updated"
  (cd "$d" && env PATH="$bin:$PATH" CALLS="$fixture/calls" CLAUDE_CODE_REMOTE=true "$@" \
    "$bash_bin" scripts/cloud-ship-bootstrap.sh >/dev/null 2>&1); rc=$?
  calls=$(cat "$fixture/calls")
}

profile scripts/cloud-setup.sh
: > "$fixture/calls"
(cd "$d" && env PATH="$bin:$PATH" CALLS="$fixture/calls" CLAUDE_CODE_REMOTE= "$bash_bin" scripts/cloud-ship-bootstrap.sh); rc=$?
check_rc "outside a cloud session: exit 0" 0 "$rc"
check "outside a cloud session: nothing runs" "" "$(cat "$fixture/calls")"

boot
check_rc "cloud setup, then a missing scanner apt installs: exit 0" 0 "$rc"
check "the cloud setup runs first, then the scanner install, retried after one update" "setup
apt-get install -y fakescan
apt-get update
apt-get install -y fakescan" "$calls"

boot
check "a scanner on PATH is not installed again" "setup" "$calls"
rm -f "$bin/fakescan"

boot SETUP_RC=1
check_rc "a failing cloud setup fails the bootstrap" 1 "$rc"
check "a failing cloud setup stops before the scanner" "setup" "$calls"

printf '# Harness profile\n\n## Cloud\r\n\r\nSetup: scripts/cloud-setup.sh\r\n' > "$d/docs/agents/harness.md"
boot
check "a CRLF profile still finds the cloud setup" "setup" "${calls%%$'\n'*}"
rm -f "$bin/fakescan"

printf '# Harness profile\n\n## Cloud\n\nVerdict: cloud-first\n' > "$d/docs/agents/harness.md"
: > "$fixture/calls"
err=$(cd "$d" && env PATH="$bin:$PATH" CALLS="$fixture/calls" CLAUDE_CODE_REMOTE=true "$bash_bin" scripts/cloud-ship-bootstrap.sh 2>&1 >/dev/null); rc=$?
check_rc "no Setup: line under ## Cloud fails the bootstrap" 1 "$rc"
check "no Setup: line: the error names the line and the file" "cloud-ship-bootstrap: no Setup: line under ## Cloud in docs/agents/harness.md" "$err"

profile None.
boot APT_INERT=1
check "Setup: None. skips the cloud setup" "apt-get install -y fakescan
apt-get update
apt-get install -y fakescan" "$calls"
check "a scanner still missing after its install fails the bootstrap" nonzero "$([ "$rc" -ne 0 ] && echo nonzero)"

boot APT_BROKEN=1
check "an apt whose update fails too fails the bootstrap" nonzero "$([ "$rc" -ne 0 ] && echo nonzero)"
check "an apt whose update fails too: no second install" "apt-get install -y fakescan
apt-get update" "$calls"

unconfigured() { sed '/^# >>> setup-skills configuration$/,/^# <<< setup-skills configuration$/d' "$1"; }
check "scripts/cloud-ship-bootstrap.sh is the template outside its configuration block" "" \
  "$(diff <(unconfigured skills/setup-skills/cloud-ship-bootstrap.sh) <(unconfigured scripts/cloud-ship-bootstrap.sh))"

finish
