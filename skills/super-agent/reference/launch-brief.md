# The launch brief

`launch.sh` generates the brief fresh for each launch, in `args.message` after
the invocation line, so send it unedited. For a re-brief, run
`scripts/brief.sh --fleet <fleet> --ledger <ledger>` with `--repo`, `--machine`
(the entry's machine), the launch's `--note` and `--skill` (the entry's `kind`:
`ship` or `triage`), and send its `brief`.

The brief has two forms, picked by `--skill` (`launch.sh` passes the owner skill
it chose; no `--skill` is `ship`). The **ship form** is the one below. The
**triage form** is the same brief without what only a ship run acts on: no merge
allowance, no standing waivers, no gate-hold line and no PR-URL-and-gate-state
ending, since a triage run opens no PR on its usual route. It adds one line for
an inline fix (a PR the triage run opens itself to ship a small proven fix gets
a review round and green CI, then stops for the super agent to merge, and the
run does not run `merge.sh`, which has no gate record for it), ends its waiting
line on "the triage outcome" in place of the PR sentence, and ends on the triage
outcome: the labels applied, any tickets filed, and the PR URL when it opened
one. Every other line is shared. Its `waivers` count is 0.

The ship form carries the **merge allowance** (merge on a clean `/ship` gate,
nothing wider), the numbered **standing waivers**, the shared-machine lines
(stop only your own processes by PID, run the heavy check under a per-repo lock
and a memory cap), the owner's allowed calls, the rulings and fleet lines that
match the launch's repo and the machine it is placed on, and the worktree,
branch and last-message rules, and the **waiting line** (a turn that ends only
to wait on its own background work ends with `Waiting on my own background
work.`, so the watcher reads it as still working; a final message is never that
line). Any hold outside them stops at the gate and comes to whoever the fleet
file's `merge_gate_ruler` names: the brief says "the super agent escalates it to
the owner" for `owner` (the default) and "the super agent rules on it and
reports to the owner" for `super-agent` (SKILL.md, Escalation). It also tells
the run that a ruling from the super agent or the owner arrives in its thread:
it acts on it and never writes it into a PR body, which records what the run did
and checked.

## Sending the launch

On `launch: true`, add each name in `needs` to `args` (`projectId`: the repo's
T3 project, from `t3_project_list` on the environment `args.environmentId`
names, this machine without one), then call `t3_thread_launch` with `args`,
never `delegate_task`: it runs only in your own project and refuses another repo
("A local task runs in this thread's project", measured). With no project there,
rerun launch with `--exclude <record.machine>` and every earlier flag; ending at
`waiting`, that is the no-project escalation: `ledger.sh --ledger <ledger>
unwait <key>` and escalate. Never link, unlink or clone a project on any
machine.
