# Super agent: how many wakes are routine, and what they cost

A one-off count for the wayfinder ticket #1367 (map #1310). It asks whether the
map's open question, "should routine wakes run on a cheaper model", is worth a
decision ticket. Counted on 2026-11-24 from the five pinned super-agent
transcripts (S1 to S5 of `super-agent-incidents.md`), with
`docs/research/super-agent-wake-count.py`. S5 was still running after the
incident research, so its later days (20 to 23 Nov) are a sixth group.

Every number below is **measured** by that script unless a sentence says
otherwise.

## How it was counted

- A **wake** is a turn start in the pinned thread: a watcher exit, a backstop
  prompt, an owner message, a compaction resume, another background task, a
  restart note. 1,004 wakes made at least one model call.
- A wake **changed nothing** when its turn made no changing call: no ledger
  write by hand, no launch, send, clean-up, issue or PR write, question or
  push. Reconcile's own ledger writes and a watcher restart do not count as a
  change. Every such wake still posted text (median 267 characters for a
  routine one), because the harness refuses a turn with none.
- Tokens are summed once per API call. **Weighted** tokens use the relative
  prices input 1, cache write 2, cache read 0.1, output 5 (**inferred** to hold
  for the models used). Raw token counts are 98% cache reads, so the weighted
  figure is the one to compare.
- Check on the method: the 10 Nov retro recorded 82 of 173 wakes doing no work
  and 139M input tokens on wakes. This count finds 85 of 177 routine wakes in
  S1 changing nothing, and 139.3M tokens on S1's watcher wakes. So that retro
  figure is S1 as a whole (6 to 10 Nov), not the day of 10 Nov.

## What the count shows

| Group | Wakes | Routine (watcher and backstop) | Routine that changed nothing | Routine share of weighted spend | No-change routine share |
|---|---|---|---|---|---|
| S1, 6 to 10 Nov | 259 | 177 | 85 | 61% | 18% |
| S2, 10 to 13 Nov | 341 | 223 | 114 | 51% | 15% |
| S3, 13 to 18 Nov | 164 | 124 | 56 | 67% | 14% |
| S4, 18 to 19 Nov | 85 | 66 | 27 | 72% | 15% |
| S5, 19 Nov | 97 | 64 | 19 | 63% | 8% |
| S5, 20 to 23 Nov | 58 | 41 | 4 | 61% | 3% |
| All | 1,004 | 695 | 305 | 60% | 14% |

By cause, all groups together:

| Cause | Wakes | Changed nothing | Weighted tokens | Share of spend |
|---|---|---|---|---|
| Watcher exit | 489 | 148 (30%) | 65.2M | 50% |
| Backstop | 206 | 157 (76%) | 13.4M | 10% |
| Owner message | 231 | 52 | 39.5M | 30% |
| Compaction resume | 38 | 24 | 6.5M | 5% |
| Other background task | 30 | 13 | 3.4M | 3% |
| Restart, harness, other scheduled | 10 | 2 | 2.8M | 2% |

What the 390 routine wakes that changed something did:

| What the wake did | Wakes | Share of all spend |
|---|---|---|
| Bookkeeping only: clean-up and ledger writes | 82 | 7% |
| A launch, with no send, question or other write | 97 | 13% |
| A send, a question to the owner, or another write | 211 | 26% |

Cost per wake:

| Wake | Median API calls | Median context per call | Median weighted tokens |
|---|---|---|---|
| Watcher, changed nothing | 4 | 185k | 75k |
| Watcher, changed something | 6 | 175k | 141k |
| Backstop, changed nothing | 2 | 174k | 40k |
| Backstop, changed something | 6 | 154k | 108k |
| Owner message, changed something | 7 | 160k | 152k |

Across all 5,838 API calls the context per call is 93k at the 10th percentile,
160k at the median and 226k at the 90th.

Models: every wake ran on Opus 5.5, except 41 wakes of S2 after the owner
switched the thread to Fable 5.2 on 13 Nov. The first call after that switch
read 0 tokens from cache and wrote 154,517, against 152,824 read and 3,733
written on the call before: a model switch rewrites the whole context once.

Routine wakes per day: median 46, most 114 (9 Nov), over 13 days with any wake.

## What it means for the cheaper-model question

1. Routine wakes are 60% of the pinned thread's spend in every period, so the
   question is large enough to decide.
2. The wakes that changed nothing are not the place for a cheaper model. They
   fell from 18% of spend to 3% as the watcher stopped exiting on no change,
   and the decisions already on the map remove the rest by not waking at all.
3. A wake costs its API calls times the context each call reads, about 160k
   tokens. That context, not the wake count, is the main term: the same wake
   over a 60k context would cost about a third (**inferred** from the weights).
4. A fifth of spend (7% bookkeeping, 13% launches) goes on routine wakes whose
   actions a script could carry out from reconcile's printed list. The larger
   part (26%) writes a step-in or a question, which needs a model.
5. Switching the model for one wake inside the thread costs a full context
   write on the first switch. Whether two models can then alternate on warm
   caches was not measured.

## Limits

- The split of a changed wake into bookkeeping, launch and judgement is by
  tool call, not by reading the turn. A launch whose placement the model
  reasoned about counts as "launch only".
- A background notification that arrived inside a running turn starts a new
  wake in this count, so a few long turns are split in two.
- Subagent calls and the compaction's own summary call are not counted.
- The weights are public relative prices, not a bill.
