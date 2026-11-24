# Super agent: the context each wake reads, and what a smaller one saves

Evidence for the wayfinder ticket #1368 (map #1310), which decides where the
pinned thread's token spend is cut. It follows `super-agent-wake-count.md` and
uses the same five pinned transcripts (6 to 23 Nov), the same wake split and
the same weights (input 1, cache write 2, cache read 0.1, output 5). Counted on
2026-11-24 with `docs/research/super-agent-context-per-wake.py`, which
reproduces the earlier headline (1,004 wakes, 5,838 API calls, 130.9M weighted
tokens).

Every number is **measured** by that script unless a sentence says otherwise.
The **context** of a call is its input plus cache read plus cache write tokens.

## What the count shows

**Spend is the context times the calls.** Cache reads are 70.7% of weighted
spend (78.1% on routine wakes), cache writes 19.4%, output 9.8%.

**Floors.** A fresh thread's first call reads 56k to 66k (median 63.6k). The
first call after a compaction reads 64k to 90k (median 76.4k, n 41), of which
a median 50k is written to cache.

**Compactions.** 41 in 17.2 days (2.4 a day). The last call before each read
228k to 262k (median 243k). 38 followed a `compact_now` call prompted by the
smart-compact hook at 80% of the auto-compact point; 3 were a bare `/compact`
after 3 to 35 idle hours (**inferred**: typed by the owner). The skill's rule,
"compact at about 100k tokens", was never kept:

| Calls above | 100k | 120k | 150k | 200k |
|---|---|---|---|---|
| Share of calls | 87.1% | 76.2% | 56.5% | 26.2% |

**Growth per wake** (the next wake's first-call context minus this one's):

| Cause | Pairs | Median | Mean |
|---|---|---|---|
| Watcher, changed nothing | 145 | 3.0k | 3.5k |
| Watcher, changed something | 318 | 7.0k | 8.5k |
| Backstop | 202 | 1.2k | 3.0k |
| Owner message | 217 | 6.5k | 10.7k |
| All | 958 | 4.6k | 7.2k |

**A fresh thread does not hold the context down.** From a floor the context
passes 100k in 1 to 4 wakes and 150k in 5 to 11 (0.9 to 3.0 hours). The median
first-call context is 159k on a thread's first day, 166k on its second and
171k from the third on. The five threads lived 3.9, 3.2, 4.9, 1.0 and 4.3
days, so the daily handover did not run daily.

**The cache is warm.** 24 of 1,004 wakes began on a cold cache, 2 of 695
routine ones. Every cache write has a 1-hour lifetime. The gap from one wake's
last call to the next wake's first is 2.6 minutes at the median and over 60
minutes for 1.9% of pairs; 17 of the 19 gaps over an hour began cold, none of
the 353 between 5 and 60 minutes did.

## What a cap would save (inferred)

Rescaling each call's context to a cap gives an upper bound that charges
nothing for the extra compactions:

| Cap | Saved, upper bound | Compactions a day | Their cost, share of spend |
|---|---|---|---|
| 100k | 33.0% | 12 to 17 | 20% to 29% |
| 80k | 43.0% | 79 to 110 | over 150% |
| 60k | 54.5% | below both floors | not reachable |

So a 100k cap is close to a wash. A sawtooth model finds the cheapest point:
a compaction costs about 135k weighted tokens (the 50k cache write at weight 2,
plus the summary call's read of the full context and its output, which this
count does not see), the context grows about 1.24k per call (7.2k per wake
over 5.8 calls), and a call costs 0.1 times the context it reads. The cost per
call of compacting at K from a 76k floor is then:

| K | Calls per cycle | Cost per call | Against today |
|---|---|---|---|
| 243k (today) | 135 | 16.9k | |
| 200k | 100 | 15.2k | 11% lower |
| 150k | 60 | 13.6k | 20% lower |
| 130k | 44 | 13.4k | 21% lower |
| 120k | 35 | 13.6k | 20% lower |
| 100k | 19 | 15.8k | 7% lower |

The curve is flat from 120k to 150k. That cost covers about 80% of total spend
(cache reads and compaction writes), so 150k is worth about 16% of the total,
at about 5 compactions a day against 9 at 120k.

Each 10k tokens off the floor is about 1k off every call's cost, about 6% of
spend. What the floor is made of was not measured.

## Limits

- The compaction's own summary call and subagent calls are not in the
  transcripts' main chain, so a compaction's cost is an estimate.
- Growth charges the next wake's prompt to the earlier wake.
- The sawtooth model assumes even growth; an owner conversation grows faster.
- The weights are public relative prices, not a bill.
