# Remote threads

## Contents

- [Why a reply file](#why-a-reply-file)
- [Steps](#steps)
- [The reply file](#the-reply-file)
- [Between wakes](#between-wakes)
- [Errors](#errors)

`scripts/` is under this skill's base directory. A **remote entry** is a
ledger entry with an `environment_id`: its thread runs on a linked machine.

## Why a reply file

`t3 thread show` has no environment flag (measured 2026-11-06), so the
scripts cannot read a remote thread themselves. You can: `t3_thread_read`
takes an `environmentId`. You save that read to a **reply file**, and
`reconcile.sh` reads the file in place of the CLI. The PR needs no file: it is
found on GitHub by branch, the same from any machine, and `watch.sh` wakes a
remote entry from GitHub alone: a PR opening on its branch (`pr-opened`), the
checks on its head commit finishing (`checks-finished`), a merge and a close.

## Steps

1. **Record.** `launch.sh record` carries the launch's environment id onto the
   entry (a `--rethread` too, clearing it for a thread on this machine). Before
   it runs, save the new thread's read as its reply file (step 2), pass
   `--worktree <path>` from it and one `--remote` (step 3) per environment
   holding an open remote entry, the new one included: its baseline reconcile
   reads it.
2. **Read.** On each wake, before `reconcile.sh` or `pulse.sh`, read every
   open remote entry's thread with `t3_thread_read`, its `environmentId` the
   entry's `environment_id`, with a low `limit` and `maxCharsPerItem`. Write
   each read to `<dir>/<thread id>.json`, one `<dir>` per environment, under
   your own scratch or state directory.
3. **Pass.** Give `reconcile.sh` (or `pulse.sh`) one `--remote <environment
   id>=<dir>` per environment that holds an open entry. `watch.sh` takes none:
   it reads no reply file.
4. **Settle.** Settle a remote thread with `t3_thread_organize` action
   `settle`, passing its `environmentId`.
5. **Remove the worktree.** Launch a scratch thread on the entry's
   environment, the way setup's probe thread runs
   ([setup](setup.md#steps) step 2). Its message asks it to run the pasted
   full text of `scripts/worktree.sh` with `bash -s -- remove --key <key>
   --path <worktree> --branch <branch> --stage <stage> --kind <kind> --merged
   <true|false>`, from the ledger entry (`merged` true only for a `ship` entry
   whose stage is `settled` or whose observed PR state is merged), and reply
   with its one JSON line. Read the reply, settle the scratch thread, and
   report a `kept` result as a local one. Never SSH.

## The reply file

One JSON object in the shape `t3 thread show --json` prints:

```json
{"thread": {"threadId": "<id>", "status": "<status>", "runCount": 3,
  "pendingRequestCount": 0, "worktreePath": "<path>", "branch": "<branch>"},
 "messages": [{"role": "assistant", "text": "<last assistant message>"}]}
```

`threadId`, `status`, `runCount` and `pendingRequestCount` are required, with
those types. `threadId` and `worktreePath` must match the ledger entry, or the
entry reads as `thread-mismatch`. `messages` needs only the last assistant
message: the merge-gate summary is read from its `text`.

## Between wakes

`watch.sh` reads no reply file. It wakes a remote entry from GitHub alone: a PR
opening on the entry's branch, the checks on its head finishing, a merge or a
close. A remote thread's own changes (a finished run, a permission hold, a new
run) are read only on a wake, when you refresh the files and reconcile, and the
backstop schedule is the wake that catches a remote thread that rested with no
PR event. A remote `task` entry with no `--branch` has no GitHub event at all,
so only that schedule notices it. Never SSH to look sooner.

## Errors

An environment with no `--remote`, a missing reply file, one that is not JSON
or one of the wrong shape gives `thread-unreadable` for that environment's
entries alone; local entries are still read. Its detail holds the
`environment_id`, a `reason` (`no-remote`, `missing`, `not-json` or `shape`)
and the `file` read. `no-remote` means pass the `--remote`; `missing` means
write the file; `not-json` and `shape` mean the save is not the thread's
`t3 thread show --json` shape, so fix how you save it, since a rerun reads the
same bytes. After a missing or stale read, read the thread again, rewrite the
file and rerun. Escalate only when a fresh `t3_thread_read` itself fails.
