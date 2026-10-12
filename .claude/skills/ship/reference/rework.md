# The rework run

`/ship <issue> --rework ["<feedback>"]` reworks the PR an earlier run of the
issue, attended or unattended, left open at the merge gate. The change to make
is the PR's unresolved review threads plus the feedback text, if any. The run
keeps the claim, the branch and the PR, and ends at a fresh merge gate. It is
attended only. `--unattended` and a task-spec run (free text in place of the
issue number) are refused with preflight's usage line, so `cloud-ship`, which
always passes `--unattended`, never starts one. `--inline` composes: the inline
lane's rules apply to the rework's own diff.

The ten phases run as SKILL.md has them. This file lists only what changes.
Where a phase's `Done when:` names a step this file replaces, the replacement
satisfies it.

## Before phase 0

`run-file init <issue> --from-profile`, adding `--rebuild` when it refuses an
existing record. Every rework run gets a new Run file, and with it a fresh
`Cap:` budget for every reviewer, since the budget counts the Run file's rounds.

## Phase 0: admission and the worktree

`preflight <issue> --rework`, adding `--feedback` when the invocation carried
text. In place of `already claimed`, `existing PR` and `existing branch` it
admits the run only when the claim is your identity's and exactly one open PR
closes the issue, its head being the one `*-<n>` branch on origin. Any other
shape is `not reworkable: <detail>`. An admitted PR with no unresolved thread,
and no text from the human, is `no feedback`. Both stops end the run before
any change and leave the claim as it is: no release, no hand-back. On `ok`,
preflight's `rework` names `{pr, branch, head_sha, worktree, threads}`.

`isolate <issue> <type> <slug> --rework` with the profile's `Carry:` files,
where `<type>` and `<slug>` are split from `rework.branch`
(`<type>/<slug>-<issue>`). It reuses the worktree an ended attended run left,
if that worktree is clean and at the PR's head (`reused: true`), and otherwise
checks the PR branch out into a new worktree. Its refusal
`existing branch: <branch> has commits origin lacks` stops the run like
`not reworkable`, with the claim unchanged.
Its `base` is the PR's head before this run: write it to the Run file's
`## Design and plan` as the **rework base**. `EnterWorktree` follows, as usual.

## Phase 1: the feedback is the spec delta

`manage-issue <issue> take` answers `claim: held`, which here meets
`claim: taken`. Read each thread in `rework.threads` whole with
`poll-pr <pr> --brief --full open`. Write one criterion per thread, then the
human's text as criteria; where they conflict, the human's text wins. A thread
is triaged the way phase 7 triages a reviewer finding: fixed, or declined with
a reason. The issue body
still binds wherever the feedback leaves it alone.

## Phase 2: the lane keys

The lane keys, and the small lane's size cap, measure the rework's own diff,
`git diff --numstat <rework base>..HEAD`, not the PR's diff against
`origin/HEAD`.

## Phase 6: the same PR

1. `open-pr <issue> --rework` pushes and answers with the open PR, creating
   none. Its `created_at` is null.
2. Rewrite the title with `update-pr-title` when it no longer matches `Grade:`.
3. Rewrite each body section the rework changed with
   `update-pr-body --section --body-file`. The Change outline and Verification
   sections always need it.
4. Read the result back with `read-pr`.
5. Skip `reflect`, since the issue already links the PR.
6. Answer each feedback thread with `reply-thread`, saying what changed, or why
   it was declined.
7. Run `resolve-thread` on each thread you fixed. A declined thread
   stays open for the human.

## Phase 7: reviewers

Rounds run as usual under a fresh `Cap:`. With `created_at` null:

- An `on-request` reviewer's round 1 skips the poll for a round the host opened
  unbidden with the PR.
- An `auto-once` reviewer exits `not reviewed: auto-once round spent by the
  earlier run`.

## Phase 9: a fresh merge gate

Write the summary as merge-gate.md says, then post it with
`comment-pr <pr> --body-file`. Then take the attended `Merge:` branch.
