# Daily handover

`scripts/` is under this skill's base directory; the ledger and fleet file are
defined in SKILL.md's `## The scripts` and `## Setup`.

The morning report starts a fresh super-agent thread, so compactions and stale
context never pile up in one. It is the one exception to SKILL.md's The loop
watcher
rule and to the Hard rules: the successor is launched without a claim and is
never recorded or watched, this thread settles itself, and its pin request is
the one push that is not a need. The old thread, in this order:

1. `scripts/handover.sh --ledger <ledger> --from $T3CODE_THREAD_ID --out
   <bearings file>`, `<bearings file>` being `bearings.md` beside the ledger.
   It refreshes the global super-agent copy when the loaded one is stale and
   writes the bearings file from the ledger. Exit 1 (the refresh failed)
   still hands over; say so in chat.
2. Stop the watcher, so two super agents never run on one ledger: TaskStop
   its background shell when its id is in hand, else `kill` the pid held in
   `<ledger>.watch`, the watcher's lock, once `ps -o args= -p <pid>` shows
   it is a `watch.sh`. No lock file means no watcher runs, and a lock whose
   pid is gone or reused is taken over by the successor's start.
3. `list_scheduled_tasks`, note the morning report's time, and
   `delete_scheduled_task` each schedule bound to this thread (the morning
   report and the backstop); retro-runs are bound to repo projects and stay.
4. Launch the successor with `t3_thread_launch` in this thread's project, no
   worktree, on this thread's provider instance and model (`t3 thread show
   $T3CODE_THREAD_ID --json`), its message two lines: `/super-agent`, then
   `Handover: read <bearings file>. Morning report at <HH:MM>.` If the launch
   fails, recreate the deleted schedules (the backstop only while an entry is
   open), start the watcher, post the `status.sh --digest` block and say in
   one chat line that the handover failed: the next morning retries.
5. Settle this thread: `t3_thread_organize` action `settle` on it.
6. Push one notification (PushNotification), and post the same line in chat:
   `Pin the new super agent: <link>`, the successor's `link`. No T3 tool pins
   a thread.

**When your first message carries a `Handover:` line, you are the
successor.** Read the bearings file it names, run After a restart or
compaction, then recreate the schedules bound to this thread with no question
asked (the owner's yes to the morning report covers them): the morning report
from `scripts/schedules.sh --fleet <fleet> --morning <HH:MM>`, `<HH:MM>` from
the `Handover:` line, and the backstop as SKILL.md's The loop step 3 says.
Then post
the `status.sh --digest` block.
