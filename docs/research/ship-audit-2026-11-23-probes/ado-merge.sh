#!/usr/bin/env bash
set -uo pipefail
src=$PWD/skills/ship-run/scripts
source "$src/host/ado.d/threads-and-lists.sh"
SHIP_PROJECT=project; SHIP_REPO=repo; SHIP_ORG_URL=https://dev.azure.com/example
azx() {
  while [ "$#" != 0 ]; do
    if [ "$1" = --body ]; then jq -c . "${2#@}" >&2; return; fi
    shift
  done
  return 2
}
host_pr_merge 7 'Squash subject' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
