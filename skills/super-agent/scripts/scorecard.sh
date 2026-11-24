#!/usr/bin/env bash
# The scorecard: one row per day counted by `jq` from the ledger and its
# archive, the guard and timer logs, and the pinned thread's transcript, so a
# new super-agent version is judged by counts and not by a model. `row` appends
# a day's row to `scorecard.jsonl` beside the ledger, replacing that day's row
# if one is there; `review` reads a week of rows against the targets.
#
#   scorecard row --ledger <file> [--day <YYYY-MM-DD>] [--thread <id>] [--transcript <file>]... [--version <v>]...
#   scorecard review --ledger <file> [--week <YYYY-MM-DD>] [--targets <file>]
#
# A day is a UTC day, the previous one by default. The transcript is every
# Claude Code transcript (`*.jsonl` under `$CLAUDE_CONFIG_DIR/projects` and
# `~/.claude*/projects`, subagents aside) that names the thread id and loaded
# the super-agent skill: a child's transcript names the id too, in its launch
# message, but never loads this skill. The thread id is `--thread`, else the
# ledger's `own_thread`, else `T3CODE_THREAD_ID`; `--transcript` reads the
# files given instead. The row is stamped with `--version`, else the version of
# the copy running this script.
#
# Logs: each `<name>-guard.jsonl` beside the ledger is a guard's, one JSON line
# per event, `{at, event: "block" | "pass"}`; `wake-timer.jsonl` is the wake
# timer's, `{at, event: "outage", minutes}`. A log not written yet is absent
# (`null` in the row), never an error.
#
# `review` covers the full week (Monday to Sunday, UTC) starting `--week`, by
# default the last full week. Each number with a target (`../scorecard/
# targets.json`: a dotted path into the row and its `max`) that went over it on
# any day of the week is one row; a guard whose log covers the four weeks ending
# with that week and blocked nothing in them is one row. A number with no target
# never raises one. Wakes, messages and the nothing-changed patterns
# (`../scorecard/nothing-changed.txt`, one regex a line) are defined in
# `../scorecard/README.md`.
#
# stdout: `row` {row, file}: the row and the file it went to · `review` {week:
#         {from, to}, days, needs: [text]}: the rows read, one line per row to raise
# exit: 0 answered · 2 usage, an unreadable ledger, no thread id, or a file
#       that could not be read or written
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || exit 2
printf '{}\n'
