#!/usr/bin/env bash
# The Host fake: a third adapter at the host seam, answering from fixtures, so a
# generic mechanic is driven end to end as a script with no host behind it and
# no fake `gh` or `az` beneath a real adapter. Selected only through
# SHIP_HOST_ADAPTER, which `ship_load_host` sources in place of
# host/$SHIP_HOST.sh; host detection still runs, so the mechanic is invoked from
# a throwaway checkout whose origin names a host.
#
#   export SHIP_FAKE=<dir> SHIP_HOST_ADAPTER=$PWD/tests/host-fake.sh
#   printf '%s\n' '{...}' > "$SHIP_FAKE/host_pr_get.1.json"
#   ( cd "$repo" && bash skills/ship/scripts/read-pr.sh 7 )
#   cat "$SHIP_FAKE/calls"
#
# The n-th call of a function answers from $SHIP_FAKE/<fn>.<n>.json, or from
# the nearest lower-numbered entry where <n> has none, so a sequence that runs
# out repeats its last entry. With no entry at or below <n> it answers from
# tests/host-fake/defaults/<fn>.json, the canonical answer per documented shape
# that tests/host-contract.test.sh holds to the `_lib.sh` contract comment; with
# neither it prints nothing and returns 0, which is a write that succeeded.
# A <fn>.<n>.fail marker makes that call print nothing and return 1, and a
# <fn>.<n>.status beside it, read only there, is printed as {"status": <n>},
# the failure answer `ship_fail_host` reads. A marker is an entry of the sequence like a fixture,
# so <fn>.1.fail alone fails every call and <fn>.1.fail with <fn>.2.json is one
# failure then an answer.
#
# Every call appends one line to $SHIP_FAKE/calls: `<fn>`, then each raw
# argument after a tab, so an argument's own spaces (a PR title) stay inside
# it, and a newline inside one (a comment body) written as `\n`.
# Counters live in files, not variables, because a mechanic calls most reads in
# a command substitution, whose subshell would lose an increment.
_host_fake_defaults=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/host-fake/defaults

_host_fake() { # <fn> <args...>
  local fn=$1 n i a; shift
  { printf '%s' "$fn"
    for a; do printf '\t%s' "${a//$'\n'/\\n}"; done
    printf '\n'
  } >> "$SHIP_FAKE/calls"
  n=$(( $(cat "$SHIP_FAKE/$fn.n" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$n" > "$SHIP_FAKE/$fn.n"
  i=$n
  while [ "$i" -gt 0 ]; do
    if [ -f "$SHIP_FAKE/$fn.$i.fail" ]; then
      [ -f "$SHIP_FAKE/$fn.$i.status" ] && printf '{"status":%s}\n' "$(cat "$SHIP_FAKE/$fn.$i.status")"
      return 1
    fi
    [ -f "$SHIP_FAKE/$fn.$i.json" ] && { cat "$SHIP_FAKE/$fn.$i.json"; return 0; }
    i=$((i - 1))
  done
  [ -f "$_host_fake_defaults/$fn.json" ] && cat "$_host_fake_defaults/$fn.json"
  return 0
}

# The same function set as host/github.sh and host/ado.sh, which
# tests/host-contract.test.sh asserts.
for _fn in host_tooling_reasons host_tooling_install host_identity host_can_push \
  host_copilot_login host_copilot_review_on_push \
  host_issue_get host_issue_comments host_issue_blockers_open host_issue_linked_prs \
  host_issue_assign host_issue_unassign host_issue_has_label host_issue_add_label \
  host_issue_remove_label host_issue_comment host_issue_close host_issue_create \
  host_issues_open host_issues_ready \
  host_pr_create host_pr_get host_pr_for_branch host_pr_checks host_pr_reviews \
  host_pr_threads host_pr_reviewer_blocked host_workflow_runs host_pr_request_review \
  host_pr_comment host_pr_set_body host_pr_set_title host_pr_reply_thread \
  host_pr_resolve_thread host_pr_merge host_prs_open; do
  eval "$_fn() { _host_fake $_fn \"\$@\"; }"
done
unset _fn
