# Scorecard baseline

The rows `scorecard row` counts for 6 to 19 November 2026 (UTC days), recounted
from the five researched super-agent sessions' transcripts and the ledger on the
owner's machine. Definitions: [the scorecard README](../skills/super-agent/scorecard/README.md). A blank cell is a day with
no message or no wake.

| Day | Open | Settled | Messages | Nothing changed | Over 1,500 | Median chars | Needs (recorded, alerted, twice) | Questions (asked, with a write) | Wakes | Wakes changing nothing | Tokens | Weighted tokens | Nothing-changed token share |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-06 | 12 | 12 | 56 | 1 | 1 | 134.5 | 0, 0, 0 | 0, 0 | 36 | 22 | 27954610 | 3534347 | 0.24 |
| 2026-11-07 | 0 | 0 | 0 | 0 | 0 |  | 0, 0, 0 | 0, 0 | 0 | 0 | 0 | 0 |  |
| 2026-11-08 | 10 | 10 | 0 | 0 | 0 |  | 0, 0, 0 | 0, 0 | 0 | 0 | 0 | 0 |  |
| 2026-11-09 | 42 | 39 | 242 | 33 | 11 | 296.5 | 0, 0, 0 | 1, 0 | 167 | 69 | 144845888 | 19874172 | 0.28 |
| 2026-11-10 | 12 | 12 | 130 | 17 | 13 | 362.5 | 0, 0, 0 | 4, 3 | 75 | 26 | 67378223 | 9956735 | 0.23 |
| 2026-11-11 | 34 | 33 | 214 | 43 | 2 | 267 | 0, 0, 0 | 2, 1 | 132 | 69 | 108382914 | 14532453 | 0.32 |
| 2026-11-12 | 26 | 26 | 152 | 22 | 7 | 416 | 7, 3, 1 | 3, 2 | 114 | 49 | 98595945 | 13249900 | 0.2 |
| 2026-11-13 | 57 | 56 | 195 | 16 | 16 | 267 | 5, 1, 0 | 0, 0 | 119 | 37 | 122911114 | 18158916 | 0.15 |
| 2026-11-14 | 1 | 0 | 1 | 0 | 1 | 5015 | 0, 0, 0 | 1, 0 | 1 | 1 | 525557 | 403442 | 1 |
| 2026-11-15 | 11 | 11 | 48 | 15 | 4 | 251.5 | 6, 0, 0 | 1, 1 | 39 | 21 | 40060691 | 5737488 | 0.28 |
| 2026-11-16 | 17 | 17 | 103 | 15 | 2 | 162 | 5, 0, 0 | 0, 0 | 59 | 25 | 67775332 | 9559159 | 0.2 |
| 2026-11-17 | 0 | 0 | 0 | 0 | 0 |  | 0, 0, 0 | 0, 0 | 0 | 0 | 0 | 0 |  |
| 2026-11-18 | 24 | 23 | 150 | 26 | 7 | 186.5 | 3, 0, 0 | 0, 0 | 90 | 34 | 82534022 | 11170197 | 0.2 |
| 2026-11-19 | 19 | 19 | 156 | 38 | 18 | 437 | 12, 9, 2 | 7, 6 | 114 | 37 | 100981890 | 13275434 | 0.14 |

Wakes by cause:

| Day | Watcher | Backstop | Owner | Compaction resume | Other background | Other scheduled | Restart or harness | Other |
|---|---|---|---|---|---|---|---|---|
| 2026-11-06 | 9 | 20 | 7 | 0 | 0 | 0 | 0 | 0 |
| 2026-11-09 | 114 | 0 | 45 | 7 | 1 | 0 | 0 | 0 |
| 2026-11-10 | 39 | 1 | 28 | 3 | 4 | 0 | 0 | 0 |
| 2026-11-11 | 51 | 53 | 23 | 5 | 0 | 0 | 0 | 0 |
| 2026-11-12 | 39 | 36 | 29 | 3 | 5 | 1 | 1 | 0 |
| 2026-11-13 | 48 | 22 | 27 | 5 | 15 | 0 | 2 | 0 |
| 2026-11-14 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| 2026-11-15 | 15 | 15 | 8 | 1 | 0 | 0 | 0 | 0 |
| 2026-11-16 | 31 | 15 | 9 | 3 | 1 | 0 | 0 | 0 |
| 2026-11-18 | 51 | 22 | 9 | 3 | 2 | 0 | 3 | 0 |
| 2026-11-19 | 54 | 19 | 34 | 4 | 1 | 0 | 2 | 0 |

## The research note's hand counts

PR #1412 recounted the 19 Nov session (S5) against the research note's hand
counts. The gaps come from definitions, not from lost data:

| Number | Hand count | Script | Why they differ |
|---|---|---|---|
| Messages | 134 | 134 | |
| Saying nothing changed | 25 | 32 | `nothing-changed.txt` also matches "Nothing needs you" after a reported change; the note's grep did not. |
| Over 1,500 characters | 15 | 15 | |
| Median length | 467 | 470.5 | The script averages the two middle lengths of an even count. |
| Needs recorded, alerted, alerted twice | 12, 7, 1 | 12, 9, 2 | The note counted push calls; the script counts `ledger.sh pushed` marks, and two needs were marked twice. |
| Question turns with a write | 3 of 11 | 6 of 7 | The note counted "why" asks over all five sessions; the script counted that day's owner turns holding a `?`. |
| Wakes | 97 | 97 | |

The day row above holds 156 messages for 19 Nov, not 134: it counts every
session that day, and S4's morning adds 22.

Recounted on 27 Nov with the script at super-agent v0.47.0, the table above
holds except in two columns. Questions read `null` on every day: since v0.45.0
(#1418) the row counts the question-flag log, which did not exist before 26
Nov, so these days have no question count. Wakes that changed nothing rise by
1 to 4 on 11, 12, 13, 18 and 19 Nov (70, 52, 41, 35, 38), and the
nothing-changed token share by up to 0.03: #1418 moved the changing-call list
into `lib/changing.sh` and narrowed it. Compare a later row with this table
only in the columns the two versions count alike.

## The gate's three counted work days

Gate #1384 compares a slice's three counted work days before it ships against
its first three after. Its first window is 24 to 26 Nov, counted on the
owner's machine:

| Day | Version | Open | Weighted tokens | Weighted tokens per open entry |
|---|---|---|---|---|
| 2026-11-24 | 0.43.0 | 23 | 9509048 | 413436.87 |
| 2026-11-25 | 0.44.0 | 20 | 10789784 | 539489.21 |
| 2026-11-26 | 0.46.0 | 24 | 15095375 | 628973.95 |

Weighted tokens per open entry per day, the mean of the three days: **527,300**
(pooled over the window, 35,394,207 over 67 open entries: 528,272). Slice 15's
target, 40% below it, is 316,380, kept in `targets.json` as `tokens.per_open`
under the slice's tag until slice 15 lands. The token counts did not move when
the three days were recounted with v0.47.0.

The rows of 24 and 25 Nov were counted before v0.45.0, so their `questions`
came from the transcript and their wakes that changed nothing from the older
changing-call list (25 Nov reads 31, not 28, under v0.47.0). The 26 Nov row
counts both the current way.
