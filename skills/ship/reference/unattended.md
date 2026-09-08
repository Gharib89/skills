# The unattended run

`--unattended` means no human is present for the run. The `cloud-ship` sibling
invokes `ship --unattended` from a cloud routine and relays the outcome; a
human can run the same command locally to reproduce a fire exactly. Nothing
here is a different pipeline: the same ten phases, with three things fixed by
the flag.

## What the flag changes

1. **Isolation is the clone.** `isolate ... --in-place`: fetch, branch from
   `origin/HEAD` in the current checkout, no worktree, no carried files. The
   sandbox clone is disposable and already isolated.
2. **A blocked stop hands back.** Every stop in SKILL.md's table that reads
   "attended: ask" becomes `manage-issue <issue> handback "<reason>"`: unassign,
   drop `ready-for-agent`, add `ready-for-human`, comment the reason
   (for a `hand-off`, the exact command the human would have run). The run
   then returns with the reason. A fire either reaches merge-ready or hands the
   issue back; it never leaves an issue claimed and spinning. Admission is
   narrower too: `ready-for-human` stops `ready-for-human: attended only`.
3. **The merge gate posts and returns.** `comment-pr` with the uncompressed
   summary, then return with the PR link. No waiting, no polling, no merge. The
   claim holds; the open PR is what keeps later fires off the issue.

Unchanged: `defer-to-ci` is the only verification disposition that proceeds
(`hand-off` and `blocked` hand back); a degraded reviewer exit still proceeds
to the merge gate on green CI and never hands back on its own; the local gate's
`unavailable` hands back with `local gate unavailable: <gates>` and never opens
the PR. Compose skills with an explicit unattended signal (`code-review`, `tdd`
and any reviewer helper); they cannot infer the absence of a human.

## The lane with no issue: `ship --unattended`

With no `<issue>`, ship runs the whole unattended lane before phase 0. It
writes nothing to the tracker until the claim in phase 1; the four stops below
leave no trace on any issue.

1. **Bootstrap.** If the profile's `## Cloud lane` names a `Bootstrap:`, run it
   first, before anything can be claimed. Non-zero exit: stop
   `bootstrap-failed`. This is sandbox-image repair, distinct from
   `## Worktree`'s `Bootstrap:`, which runs in every lane after isolate.
2. **PR cap.** `list-prs --open`; at or above the profile's `PR cap:` (default
   3, `none` disables), stop `pr-queue-full`. One operator's merge-review queue
   is the bottleneck, not the backlog.
3. **Select.** `select`: the oldest-created open issue labelled `ready-for-agent`,
   with no assignee and no open blocker, walking candidates ascending
   until one passes. No candidate: stop `nothing-ready`, the one clean no-op.
   The host's blocker query exists and failed: stop `blockers-unavailable`;
   shipping a dependent issue out of order builds a PR on unmerged work, so
   never guess order.
4. **Run** phases 0 to 9 on the selected issue as `ship <issue> --unattended`.
5. **Report**: the PR link and the merge summary's location, or the stop
   reason verbatim (ship's own reasons pass through unchanged, including
   `host-unreachable` from preflight).

The repo is derived from the clone's `origin` remote; no repo name is passed
anywhere.
