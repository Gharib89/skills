# Remote threads

## Contents

- [How a remote thread is read](#how-a-remote-thread-is-read)
- [Steps](#steps)
- [Between wakes](#between-wakes)
- [Errors](#errors)
- [Machine checks](#machine-checks)

`scripts/` is under this skill's base directory. A **remote entry** is a
ledger entry with an `environment_id`: its thread runs on a linked machine.

## How a remote thread is read

`t3 thread show` has no environment flag (measured 2026-11-06), so the scripts
read a remote thread with the `t3` on its machine, over SSH (`lib/remote.sh`):
the fleet file's machine whose `environment_id` is the entry's, through its
`ssh` string. One SSH call reads every open thread on that machine, and
`reconcile.sh`, `pulse.sh`, `watch.sh` and `launch.sh record` share it. You
read no remote thread by hand. The PR is found on GitHub by branch, the same
from any machine.

## Steps

1. **Record.** `launch.sh record` carries the launch's environment id onto the
   entry (a `--rethread` too, clearing it for a thread on this machine) and
   reads the thread's worktree on its machine. Its baseline reconcile reads the
   thread there too.
2. **Settle.** Settle a remote thread with `t3_thread_organize` action
   `settle`, passing its `environmentId`.
3. **Remove the worktree.** A write goes over a T3 environment, not SSH
   (ADR 0023). Launch a scratch thread on the entry's environment
   (`t3_thread_launch` with its `environmentId`). Its message asks it to run
   the pasted full text of `scripts/worktree.sh` with `bash -s -- remove --key
   <key> --path <worktree> --branch <branch> --stage <stage> --kind <kind>
   --merged <true|false>`, from the ledger entry (`merged` true only for a
   `ship` entry whose stage is `settled` or whose observed PR state is
   merged), and reply with its one JSON line. Read the reply, settle the
   scratch thread, and report a `kept` result as a local one.

## Between wakes

`watch.sh` reads a remote thread every poll, like a local one, so a finished
run, a permission hold and every other local wake reason wake you for it too.
Each rest it reads and the wake that reports it are lines of
`remote-watch.jsonl` beside the ledger, which the scorecard's `remote` row
times.

## Errors

A machine that cannot be read gives `thread-unreadable` for its entries alone;
local entries and other machines are still read. Its detail holds the
`environment_id`, the `machine` and a `reason`: `ssh` (the call failed, with
SSH's own reason as `ssh`), `no-ssh` (no fleet machine with that environment
has an `ssh` string: add it, as [setup](setup.md) says) or `shape` (the
machine's `t3` answered no thread JSON, so it does not know the thread).

`watch.sh` raises no `thread-unreadable`. While a machine fails, it watches
that machine's entries from GitHub alone (a PR opening on the branch, its
checks finishing, a merge, a close) and logs each failed read. After 5 minutes
unread it exits once with `machine-unreadable`, naming the `machine`, the
`reason` and `since`: make one offer in chat naming the machine (check it or
fix its `ssh` string), with no phone alert, and start the watcher again. A
restarted watcher does not offer the same outage again, and the next good read
clears it with no wake.

## Machine checks

Reads go over SSH and writes over a T3 environment (ADR 0023).
`scripts/machine-check.sh <machine> <check>` runs one fixed, read-only check
over the machine's tested `ssh` string in the fleet file (`--help` lists the
checks; `log` takes a systemd unit or a file listed under the machine's
`logs`). It takes a linked or a check-only machine. Run an asked check inline,
in an answer-only turn too, and post its printed line. On `needs-root`, offer
the owner the read to run themselves. On `unreachable`, post SSH's reason as
the answer; placement keeps using T3's reachability. The call guard refuses a
direct `ssh`, `scp` or `rsync` call, so the script is the only route.
