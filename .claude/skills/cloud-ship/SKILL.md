---
name: cloud-ship
description: >-
  Run one fire of a scheduled cloud routine: invoke `ship` unattended and relay
  its outcome. Composes `ship`. Use only from a cloud routine's prompt; a human
  runs `/ship`.
metadata:
  version: 1.0.1
---

# cloud-ship

One **fire**: one selected issue driven to one merge-ready PR, ending at the
merge gate with no human present. Everything a fire does is `ship`'s: the
sandbox tooling, the profile's cloud bootstrap, the PR cap, the selection, the
claim, the branch, the isolation, the hand-back and the merge summary. This
skill adds the invocation and the relay, nothing else. The copy under
`.claude/skills/cloud-ship` is a **derived copy**, the same bytes in every repo,
changed upstream in `skills/cloud-ship/` and refreshed through the command the
repo's `### Ship` block in CLAUDE.md carries.

## The fire

1. **Invoke `ship` unattended.** Call the Skill tool with skill `ship` and
   arguments `--unattended`, no issue number. Ship runs the whole unattended
   lane (`reference/unattended.md` in its own folder): tooling, the profile's
   `## Cloud lane` bootstrap, the PR cap, selection, then phases 0 to 9 on the
   selected issue, posting the merge summary as a PR comment and returning.
2. **Relay.** Report ship's step-5 result verbatim, prefixed with
   `cloud-ship <version>` (the `metadata.version` above): the PR link and where
   the merge summary is, or the stop reason as ship named it
   (`bootstrap-failed`, `pr-queue-full`, `nothing-ready`,
   `blockers-unavailable`, `host-unreachable`, or any stop from ship's table).
   `nothing-ready` is the one clean no-op; every other stop is a fire worth
   reading in the routine log.

## The one invariant

Git, the tracker, the mechanics and the merge gate are ship's, on both sides of
the invocation: hand the sandbox clone over untouched, for `isolate --in-place`
to branch, and let ship run every mechanic itself. The fire ends where ship
returns: relay what it said and stop there, because a human merges from the PR,
and the open PR and the claim keep the next fire off that issue. This
skill contributes the two steps above and nothing else, so a behaviour defined
here would be a second definition of one ship already owns. The tracker is where
that bites hardest: leave every claim, label, comment and hand-back to ship,
which holds them from selection onwards, and before selection there is no issue
to write to anyway.

## The routine prompt

One sentence, identical in every repo, because the derived copy is the same
bytes everywhere and ship derives the repo from the clone's remote:

```
Run the cloud-ship skill.
```
