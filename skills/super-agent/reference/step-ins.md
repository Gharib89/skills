# The launch message and the step-ins

## Contents

- [The launch message](#the-launch-message)
- [Sending the launch](#sending-the-launch)
- [The step-ins](#the-step-ins)

A supervised thread hears from you through its **launch message**, then only
through a **step-in** when it reaches one of five situations. Nothing else is
sent into it: no reminder, no ruling it has not reached, no broadcast to running
threads (ADR 0020).

## The launch message

`launch.sh` writes it into `args.message`: the owner-skill invocation (`/ship
<n>`, `/triage <n>`), plus one `Note: <text>` line when you passed `--note`.
Send it unedited. Every rule the run follows lives in its owner skill, its
repo's ship profile or the global rules it loads, so nothing rides on the
launch message: no waiver, ruling or merge allowance. The one exception is a
`/triage` message, which carries a contract line after the invocation (and
before the note): a turn that only waits on its own background work ends on the
waiting line, and the final message is the triage outcome. The triage skill is
upstream, so no `SKILL.md` this repo owns can say it; ship's does.

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

## The step-ins

Post with `t3_thread_send`, after reading the thread's last messages in a small
slice. Each carries only what its moment needs, and these five are the only
ones:

1. **Stall 1, the nudge** ([stall ladder](stall-ladder.md#the-ladder) rung 1):
   one line telling the run its ticket is not done and to carry on.
2. **Stall 2, the missing fact** (rung 2): only what the thread's last messages
   show it lacks, such as a fact, a file or a decision. Never the launch
   message or any rule again.
3. **A gate hold** the run stopped on
   ([wake-actions](wake-actions.md#merge-gate-holds)): the one standing waiver
   from the fleet file's `waivers`, or the one ruling scoped to the repo (the
   `scoped` rows of `ledger.sh --ledger <ledger> scoped --repo <owner/name>`
   for the run's repo), whose condition matches the hold, quoted word for
   word, telling the run to merge through `merge.sh` and name that waiver in
   its PR body. A hold none matches goes to whoever `merge_gate_ruler` names,
   and the step-in carries that ruling once it exists. A triage run that
   reports a PR it opened to ship a small proven fix inline is at a gate too,
   and you never merge it. Assign the issue to the gh login the repo needs
   (`gh issue edit <n> --repo <owner/name> --add-assignee <login>`), because
   `--rework` admits only an issue its own identity holds, then launch `/ship
   <n> --rework "<feedback>"` with `t3_thread_launch` on the instance and tier
   `route.sh` picks ([Routing](routing.md)), never `launch.sh` (it would build a
   `/triage` message for this issue). Place it where the triage entry ran: the
   entry's `machine` and `environment` (`ledger.sh --ledger <ledger> get
   <key>`) as `environmentId` where they name another machine, and the repo's
   `projectId` resolved as in [Sending the launch](#sending-the-launch). Its
   feedback text, such as "take this PR through review and the merge gate", is
   what stops `no feedback`; a plain `/ship <n>` stops `existing PR`. Point
   the ticket's
   entry at the new thread with `ledger.sh --ledger <ledger> rethread <key>
   --thread <id> --worktree <the launched thread's path> --branch <the PR's
   `*-<n>` head branch> --kind ship`, plus the `--instance`, `--model` and
   `--effort` route picked, so the merge is verified like any ship PR. The
   run's gate, review round and `merge.sh` merge the PR. A `not reworkable`
   stop, such as `branch mismatch` when the PR does not head on the one
   `*-<n>` branch, is a need for the owner.
4. **The owner's answer to a need the thread raised**: the answer, as the owner
   gave it, into the thread whose need it settles.
5. **A hard finding from verification**: the verified acceptance-criterion gap
   you send back to the thread ([stall ladder](stall-ladder.md#the-ladder)).

The run acts on a step-in and writes none of it into its PR body, except a
waiver that passed the gate, which the body names.
