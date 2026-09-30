#!/usr/bin/env bash
# The host adapters' RETURN traps must disarm themselves. Bash keeps a RETURN
# trap armed after the function that set it returns, so it fires again when that
# function's caller returns, where the callee's `local` is out of scope and
# `set -u` aborts the mechanic ("f: unbound variable"). No mechanic calls an
# adapter function from inside a helper today; the first that does would break.
# Each case calls one trapped adapter function from a wrapper function under
# `set -uo pipefail`, its transport stubbed as a shell function, in a subshell
# so an abort is an exit code and not the end of this file. A last case reads the
# adapter sources as files: every RETURN trap under the skills clears itself.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# GitHub: host_issue_comment's temp file exists only for its trap to remove. The
# stub for host_pr_comment records the path it was handed.
out=$(
  set -uo pipefail
  SHIP_OWNER=owner SHIP_REPO=repo
  source skills/ship/scripts/_lib.sh
  source skills/ship/scripts/host/github.sh
  host_pr_comment() { printf '%s' "$2" > "$tmp/gh-file"; }
  wrapper() { host_issue_comment 1 "a comment"; }
  wrapper
  echo "survived: $(trap -p RETURN | wc -l | tr -d ' ')"
) 2>"$tmp/gh-err"; rc=$?
check_rc "github: the script survives a wrapper's return" 0 "$rc"
check "github: no RETURN trap is left armed" "survived: 0" "$out"
check "github: the temp file is gone" "gone" "$([ -n "$(cat "$tmp/gh-file" 2>/dev/null)" ] && [ ! -e "$(cat "$tmp/gh-file")" ] && echo gone || echo "still there")"

# Azure DevOps: host_pr_resolve_thread, with `invoke` answering a fixture.
out=$(
  set -uo pipefail
  SHIP_ORG_URL=https://dev.azure.com/org SHIP_PROJECT=proj SHIP_REPO=repo
  source skills/ship/scripts/_lib.sh
  source skills/ship/scripts/host/ado.sh
  invoke() { echo '{"status":"fixed"}'; }
  wrapper() { host_pr_resolve_thread 7 3 >/dev/null; }
  wrapper
  echo "survived: $(trap -p RETURN | wc -l | tr -d ' ')"
) 2>"$tmp/ado-err"; rc=$?
check_rc "azure devops: the script survives a wrapper's return" 0 "$rc"
check "azure devops: no RETURN trap is left armed" "survived: 0" "$out"

# The rest of the sites share the form; a trap that does not clear itself is the
# defect, wherever it sits. Any line arming a RETURN trap (its first word is not
# `-`, which disarms) must end its body with the disarm, in either quote.
check "no RETURN trap under the skills leaves itself armed" "" \
  "$(grep -rnE 'trap [^-].* RETURN' skills --include='*.sh' | grep -vE "trap - RETURN['\"] RETURN")"

finish
