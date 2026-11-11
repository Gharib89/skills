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
hold outside them stops at the gate and comes to you as an escalation
(SKILL.md, Escalation).
