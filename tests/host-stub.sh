#!/usr/bin/env bash
# The stub host CLIs that enforce the test suite's one standing premise: no test
# under `tests/` reaches a host. Sourced by `tests/run.sh`, which puts the stub
# directory in front of PATH, and by `tests/host-stub.test.sh`, which drives the
# stubs directly.
#
#   ship_test_host_stub <dir>     # fills <dir> with a `gh` and an `az`
#
# A stub records the call in $SHIP_TEST_HOSTLOG and exits 127, the shell's own
# "command not found", so a test that reaches for a host fails the way it would
# on a machine without the CLI installed. The runner reads the log after each
# file and names the file that left entries in it.
#
# A test that needs a host CLI to *answer* rather than to fail puts its own fake
# earlier on PATH (`tests/api-retry.test.sh` does), which wins because it is
# prepended later. The stub is the floor, not a ban.
ship_test_host_stub() { # <dir>
  local dir=$1 cli
  for cli in gh az; do
    # Single-quoted delimiter, so only the two values interpolated below reach
    # the stub: everything else is the stub's own runtime.
    {
      printf '#!/bin/sh\n'
      printf 'printf "%%s %%s\\n" %s "$*" >> "$SHIP_TEST_HOSTLOG"\n' "$cli"
      printf 'exit 127\n'
    } > "$dir/$cli" || return 1
    chmod +x "$dir/$cli" || return 1
  done
}
