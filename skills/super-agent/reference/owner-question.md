# An owner question

An **owner question** is any owner message that asks and tells nothing: why,
what, when, how. It starts an **answer-only turn**. SKILL.md's section holds the
rule; this page holds what backs it.

## The turn

- The reply opens with the answer, offers the fix as a numbered option, and
  changes nothing. Only read-only calls and the watcher restart run in it.
- A message that asks and tells gets the answer first, then exactly the told
  action. A request phrased as a question ("can you launch 1234?") is a request.
- The answer is built from the record, re-read in that turn: a ledger entry, a
  dated ruling, a script's output, each fact naming its source. What no record
  holds is said as recollection or as not known, never reconstructed.
- No reconcile runs in it, unless the watch guard asks: the watcher compares
  against the last reconcile, so one here would move its baseline and leave work
  already seen to wait for the next change or the hourly backstop.

## The offered fix

Record it as a need with the reason word `ask-first`, an offer, under a key tied
to no ledger entry, `task:ask-first-<slug>` (`<slug>` a few words naming the
fix):

```sh
scripts/ledger.sh --ledger <ledger> need task:ask-first-close-1234 \
  --action 'Close acme/widgets#1234 as a duplicate?' --reason ask-first
```

It shows in the status block and survives a compaction, and no later wake
carries it out. The owner's reply is the go: do that option, then `unneed` the
key.

## The two hooks

Both are in the super agent folder's generated settings
([setup](setup.md#the-guard-hook)); neither refuses anything.

- **The question flag**, `scripts/question-flag.sh`, a UserPromptSubmit hook. A
  prompt holding a `?` and carrying no T3 sender prefix is flagged: its
  `prompt_id` goes to `question-flag.jsonl` beside the ledger and one reminder
  line to the turn. A prompt T3 sent for an agent, a scheduled task or a
  finished background shell starts with `[T3 Code:` or `<task-notification>`; an
  owner-typed one has no prefix (measured against live hook input). You still
  judge question or request: a misfire costs one ignored line.
- **The observe hook**, `scripts/observe.sh`, a PreToolUse hook. Every tool call
  carries the `prompt_id` of the prompt that started its turn, so the hook logs
  each changing call whose id the flag logged, and passes it. The next turn has
  a new id, so it is not flagged, and no flag file is shared.

A **changing call** is on a named list: the T3 calls that launch, send to,
interrupt, organize, configure or schedule; the acting scripts (`launch.sh`,
`claim.sh`, `worktree.sh remove`, `merge.sh`, `cleanup.sh`, `intake.sh`,
`handover.sh`) and `ledger.sh`'s write verbs other than `need`; the `gh` and
`git` verbs that write; Edit, Write, MultiEdit and NotebookEdit. A machine check
is none. A call missing from the list goes uncounted, as with the state guard. A
hook that cannot judge allows the call and logs `unjudged`.

## The number

The scorecard's `questions` counts the flagged owner turns of a day (`asked`)
and those holding a changing call (`with_write`, baseline 3 of 11, target 0),
and the weekly review lists each such turn: read it and take its sender from
`t3_thread_read`.
