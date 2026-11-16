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
launch message: no waiver, ruling, merge allowance or output contract.

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
   `briefed` rows of `ledger.sh --ledger <ledger> briefed` whose `repo` is the
   run's), whose condition matches the hold, quoted word for word, telling
   the run to merge through `merge.sh` and name that waiver in its PR body. A
   hold none matches goes to whoever `merge_gate_ruler` names, and the step-in
   carries that ruling once it exists. A triage run that reports a PR it opened
   to ship a small proven fix inline is at a gate too: tell it the PR gets a
   review round and green CI, then stops for you to merge, without `merge.sh`,
   which has no gate record for it.
4. **The owner's answer to a need the thread raised**: the answer, as the owner
   gave it, into the thread whose need it settles.
5. **A hard finding from verification**: the verified acceptance-criterion gap
   you send back to the thread ([stall ladder](stall-ladder.md#the-ladder)).

The run acts on a step-in and writes none of it into its PR body, except a
waiver that passed the gate, which the body names.
