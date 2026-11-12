# The launch brief

`launch.sh` generates the brief fresh for each launch, in `args.message` after
the invocation line, so send it unedited. For a re-brief, run
`scripts/brief.sh --fleet <fleet> --ledger <ledger>` with `--repo`, `--machine`
(the entry's machine) and the launch's `--note`, and send its `brief`.

It carries the **merge allowance** (merge on a clean `/ship` gate, nothing
wider), the numbered **standing waivers**, the shared-machine lines (stop only
your own processes by PID, run the heavy check under a per-repo lock and a
memory cap), the owner's allowed calls, the rulings and fleet lines that match
the launch's repo and the machine it is placed on, and the worktree, branch and
last-message rules, and the **waiting line** (a turn that ends only to wait on
its own background work ends with `Waiting on my own background work.`, so the
watcher reads it as still working; a final message is never that line). Any
hold outside them stops at the gate and comes to whoever the fleet file's
`merge_gate_ruler` names: the brief says "the super agent escalates it to the
owner" for `owner` (the default) and "the super agent rules on it and reports to
the owner" for `super-agent` (SKILL.md, Escalation). It also tells the run that
a ruling from the super agent or the owner arrives in its thread: it acts on it
and never writes it into a PR body, which records what the run did and checked.

## Sending the launch

On `launch: true`, add each name in `needs` to `args` (`projectId`: the repo's
T3 project, from `t3_project_list` on the environment `args.environmentId`
names, this machine without one), then call `t3_thread_launch` with `args`,
never `delegate_task`: it runs only in your own project and refuses another repo
("A local task runs in this thread's project", measured). With no project
there, rerun launch with `--exclude <record.machine>` and every earlier flag;
ending at `waiting`, that is the no-project escalation: `ledger.sh unwait <key>`
and escalate. Never link, unlink or clone a project on any machine.
