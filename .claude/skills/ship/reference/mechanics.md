# The mechanics: what all of them have in common

`scripts/` holds one executable per deterministic step, and a mechanic is the
only way a ship run touches the host, though not every one does: `run-file`
writes the run's own record and nothing else. `SKILL.md` says which mechanic each phase
runs and what it decides there; this file says how every one of them answers,
so the rule is read once rather than re-derived per call.

## Ask the script what its flags are

For a mechanic's flags, run `<base directory>/scripts/<mechanic>.sh --help`.
Every mechanic answers it with its usage line on stdout, exit 0 and nothing on
stderr, before it loads a host adapter and without reaching the host, which is
why `SKILL.md`'s table carries phases and not flags: a table can go stale
against the script, and `--help` cannot. Only the first argument is read, so
`poll-pr.sh 42 --help` is a poll of PR 42 and not a help call.

## The exit codes

Each prints one JSON verdict on stdout, a failing step's last 40 log lines on
stderr, and exits `0` ok, `1` the mechanic's own not-ok answer, `2` tooling. A
malformed invocation is tooling, never exit 1: a missing or empty positional, a
flag where a positional belongs and a flag without its value all print
`{"error": "<usage>"}` and exit 2, as an unknown flag does. A leading `--help`
is the one exception, answered above before any of these guards runs. Exit 1 is an answer,
not always a fault: `nothing-ready` from `select`, a not-actionable `preflight`
and a `poll-pr` window that closed are all exit 1 and none is red.

## What a failed write says

A failed write to an open PR's body or title, a comment or a thread reply
carries the host's `status` beside its `error`: a 5xx or a 429 outlasted the
mechanic's own backoff, so retrying is the fix; any other number is the request
itself, so read the body you sent. `null` is neither: the call never got an HTTP
answer at all, so the host or the tooling between you and it is what to look at.
`open-pr` and `file-issue` answer with the error alone, and their stderr carries
the host's own message. Read the JSON, then decide.

## The vocabulary a read comes back in

Reads come back in one vocabulary on both hosts: checks
`pending|success|failure`, mergeable `clean|conflict|unknown`, review
`approved|changes|comment`, and threads as `resolved: true|false` per thread, or
the whole `threads` field as the string `"unavailable"` when the state could not
be read.

## Run them inline

Run mechanics **inline**: they project their own output, so a subagent there
burns budget to relay what an exit code already says. Poll loops are bounded
and foreground; reaching the bound is never permission to proceed. Re-run to
extend, or pass a wider `--timeout` up front when the profile's `Legs:` names a
leg you know is slower than the bound.
