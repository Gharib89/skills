#!/usr/bin/env bash
# prepare driven end to end over the Host fake (tests/host-fake.sh): a throwaway
# GitHub-origin checkout carrying its own profile, so the `## Cloud lane`
# `Bootstrap:` it runs is a fixture script that appends to the fake's call log.
# That one log then holds both steps in the order they ran, which is the claim:
# inside a cloud sandbox (CLAUDE_CODE_REMOTE=true) or with --unattended, the
# host's tooling step runs first and the bootstrap second; outside both, neither.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mech=$PWD/skills/ship/scripts/prepare.sh
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
repo=$work/repo; export SHIP_FAKE=$work/fake
mkdir -p "$repo/docs/agents" "$repo/scripts" "$SHIP_FAKE"
git -C "$repo" init -q
git -C "$repo" remote add origin https://github.com/owner/repo.git
export SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh

printf '#!/usr/bin/env bash\necho bootstrap >> "$SHIP_FAKE/calls"\necho installed\n' > "$repo/scripts/boot.sh"
printf '#!/usr/bin/env bash\necho bootstrap >> "$SHIP_FAKE/calls"\necho apt refused; exit 3\n' > "$repo/scripts/boot-fail.sh"
chmod +x "$repo/scripts/boot.sh" "$repo/scripts/boot-fail.sh"

profile() { # <bootstrap value>
  printf '# Ship profile\n\n## Worktree\n\nBootstrap: scripts/boot-fail.sh\n\n## Cloud lane\n\nPR cap: 3\nBootstrap: %s\n' "$1" \
    > "$repo/docs/agents/ship.md"
}
run()   { ( cd "$repo" && bash "$mech" "$@" ); }
reset() { rm -f "$SHIP_FAKE"/*; }
steps() { jq -c '[.steps[] | "\(.step):\(.status)"]' <<<"$1"; }

profile scripts/boot.sh

reset
out=$(env -u CLAUDE_CODE_REMOTE bash -c 'cd "$1" && bash "$2"' _ "$repo" "$mech"); rc=$?
check_rc "outside a cloud sandbox, an attended run prepares nothing and exits 0" 0 "$rc"
check "and says it is not in a sandbox, with no steps" 'false []' \
  "$(jq -r '"\(.sandbox) \(.steps | tojson)"' <<<"$out")"
check "and neither step ran" '' "$(cat "$SHIP_FAKE/calls" 2>/dev/null)"

reset
out=$(CLAUDE_CODE_REMOTE=true run); rc=$?
check_rc "in a cloud sandbox, both steps pass and it exits 0" 0 "$rc"
check "both steps are reported ran, tooling first" '["tooling:ran","bootstrap:ran"]' "$(steps "$out")"
check "the host's tooling ran before the Cloud lane bootstrap, and the Worktree one never ran" \
  "$(printf 'host_tooling_reasons\nbootstrap')" "$(cat "$SHIP_FAKE/calls")"

reset
out=$(env -u CLAUDE_CODE_REMOTE bash -c 'cd "$1" && bash "$2" --unattended' _ "$repo" "$mech"); rc=$?
check_rc "--unattended prepares off the sandbox too, as the unattended lane always has" 0 "$rc"
check "with both steps, in order" '["tooling:ran","bootstrap:ran"]' "$(steps "$out")"

reset
profile scripts/boot-fail.sh
out=$(CLAUDE_CODE_REMOTE=true run 2>"$work/err"); rc=$?
check_rc "a failed bootstrap is the mechanic's not-ok answer" 1 "$rc"
check "which names the bootstrap as the failing step" 'bootstrap false' "$(jq -r '"\(.failed) \(.ok)"' <<<"$out")"
check "and carries the step's tail on stderr" 'apt refused' "$(cat "$work/err")"

reset
profile scripts/boot.sh
printf 'gh not installed\n' > "$SHIP_FAKE/host_tooling_reasons.1.json"
: > "$SHIP_FAKE/host_tooling_install.1.fail"
out=$(CLAUDE_CODE_REMOTE=true run 2>/dev/null); rc=$?
check_rc "host tooling that stays missing is the not-ok answer" 1 "$rc"
check "which names the tooling step and never reaches the bootstrap" 'tooling ["tooling:failed"]' \
  "$(jq -r '"\(.failed) \([.steps[] | "\(.step):\(.status)"] | tojson)"' <<<"$out")"
check "and the missing tool is named" '["gh not installed"]' "$(jq -c .missing <<<"$out")"

reset
profile '`scripts/boot.sh`  '
out=$(CLAUDE_CODE_REMOTE=true bash -c 'cd "$1/scripts" && bash "$2"' _ "$repo" "$mech"); rc=$?
check_rc "from a subdirectory, a backticked Bootstrap: runs from the checkout root" 0 "$rc"
check "with both steps ran" '["tooling:ran","bootstrap:ran"]' "$(steps "$out")"

reset
profile None.
out=$(CLAUDE_CODE_REMOTE=true run); rc=$?
check_rc "Bootstrap: None. still exits 0" 0 "$rc"
check "with the bootstrap skipped" '["tooling:ran","bootstrap:skipped"]' "$(steps "$out")"

reset
rm -f "$repo/docs/agents/ship.md"
out=$(CLAUDE_CODE_REMOTE=true run); rc=$?
check_rc "no profile leaves the stop to preflight, and exits 0" 0 "$rc"
check "with the bootstrap skipped" '["tooling:ran","bootstrap:skipped"]' "$(steps "$out")"

out=$(run --x); rc=$?
check_rc "an unknown flag is a malformed invocation" 2 "$rc"
check "answered with the usage line" 'usage: prepare [--unattended]' "$(jq -r .error <<<"$out")"

finish
