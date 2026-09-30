#!/usr/bin/env bash
# This repo is both the source of the shared skills and a consumer of them, so
# `.claude/skills/<n>` must be the bytes of `skills/<n>`. A change to a skill
# that was not followed by the refresh line fails here. The `derived-copies`
# gate in scripts/local-gate.sh and `scripts/check.sh full` run this.
#
#   scripts/derived-copies-check.sh
#
# stdout: one line per difference
# exit: 0 identical · 1 a difference · 2 tooling
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

rc=0
for s in ship cloud-ship setup-skills update-skills setup-harness grill-with-artifact; do
  [ -d ".claude/skills/$s" ] || { echo "missing derived copy: .claude/skills/$s"; rc=1; continue; }
  diff -rq "skills/$s" ".claude/skills/$s" || rc=1
  # diff -rq compares content only. A mechanic that loses its executable bit
  # on one side passes that check and then fails at run time, so compare the
  # set of executable files too.
  diff <(cd "skills/$s" && find . -type f -perm -u+x | sort) \
       <(cd ".claude/skills/$s" && find . -type f -perm -u+x | sort) \
    || { echo "executable bits differ between skills/$s and .claude/skills/$s"; rc=1; }
done
jq -e '.skills | has("ship") and has("cloud-ship") and has("setup-skills") and has("update-skills") and has("setup-harness") and has("grill-with-artifact")' skills-lock.json >/dev/null \
  || { echo "skills-lock.json does not record all six self-installed skills"; rc=1; }
# The profile schema number across its three files: scripts/profile-schema-check.sh.
scripts/profile-schema-check.sh || rc=1
# Every pinned ref a skill states against the lock's: scripts/pin-check.sh.
scripts/pin-check.sh || rc=1
exit $rc
