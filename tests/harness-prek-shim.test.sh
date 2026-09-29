#!/usr/bin/env bash
# skills/setup-harness/reference/gap-report.md: the mark a re-run reads to tell
# a prek shim installed with --allow-missing-config from an older one. The
# subject is the real prek: the mark the row names is in the shim the flag
# writes and absent from the default shim. Without prek on PATH, no case runs.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
source tests/lib.sh

mark=$(sed -n 's/^| prek'"'"'s git shim.* lacking `\([^`]*\)`.*/\1/p' skills/setup-harness/reference/gap-report.md)
check "the gap row names the shim's mark" "--skip-on-missing-config" "$mark"

if command -v prek >/dev/null; then
  fixture=$(mktemp -d); trap 'rm -rf "$fixture"' EXIT
  # <name> [<flag>]: the pre-commit shim prek writes into a fresh repo.
  shim() {
    git init -q "$fixture/$1" && (cd "$fixture/$1" && prek install ${2:+"$2"} >/dev/null 2>&1)
    cat "$fixture/$1/.git/hooks/pre-commit"
  }
  case $(shim flagged --allow-missing-config) in *"$mark"*) got=present ;; *) got=absent ;; esac
  check "--allow-missing-config writes the mark" present "$got"
  case $(shim default) in *"$mark"*) got=present ;; *) got=absent ;; esac
  check "a default shim lacks the mark" absent "$got"
fi

finish
