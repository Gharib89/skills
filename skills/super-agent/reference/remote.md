# Remote threads

## Contents

- [Why a reply file](#why-a-reply-file)
- [Steps](#steps)
- [The reply file](#the-reply-file)
- [Refreshing mid-watch](#refreshing-mid-watch)
- [Errors](#errors)

`scripts/` is under this skill's base directory. A **remote entry** is a
ledger entry with an `environment_id`: its thread runs on a linked machine.

## Why a reply file

`t3 thread show` has no environment flag (measured 2026-11-06), so the
scripts cannot read a remote thread themselves. You can: `t3_thread_read`
takes an `environmentId`. You save that read to a **reply file**, and
`reconcile.sh` and `watch.sh` read the file in place of the CLI. The PR needs
no file: it is found on GitHub by branch, the same from any machine.

## Steps

1. **Record.** On a remote launch, pass `--environment
   <placed.environment_id>` to `ledger.sh add`. A `rethread` to a remote
   thread keeps the entry's `environment_id`, so the new thread must run in
   the same environment.
2. **Read.** Before each `reconcile.sh` run and each `watch.sh` start, read
   every open remote entry's thread with `t3_thread_read`, its
   `environmentId` the entry's `environment_id`, with a low `limit` and
   `maxCharsPerItem`. Write each read to `<dir>/<thread id>.json`, one `<dir>`
   per environment, under your own scratch or state directory.
3. **Pass.** Give `reconcile.sh` and `watch.sh` one `--remote <environment
   id>=<dir>` per environment that holds an open entry.
4. **Settle.** Settle a remote thread with `t3_thread_organize` action
   `settle`, passing its `environmentId`.

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

## Refreshing mid-watch

`watch.sh` re-reads the reply files every poll, but they change only when you
rewrite them. A remote thread's own changes (a finished run, a permission
hold, a new run) reach a running watcher only as fast as you refresh its file;
its PR merging or closing is read from GitHub each poll and wakes you on time.
So on every wake, the backstop schedule included, refresh the files before
reconciling. To catch a remote change sooner, rewrite the files while the
watcher runs, or stop it and start it again after a fresh read.

## Errors

An environment with no `--remote`, a missing reply file, or one that is not
the thread's JSON gives `thread-unreadable` with the `environment_id` in its
detail, for that environment's entries alone; local entries are still read.
That is a missing or stale read, not a dead thread: read the thread again,
rewrite the file, and rerun with the `--remote` in place. Escalate only when a
fresh `t3_thread_read` itself fails.
