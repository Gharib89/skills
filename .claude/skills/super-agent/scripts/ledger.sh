#!/usr/bin/env bash
# Read and write the super agent's ledger: one entry per ticket it holds, plus
# the owner's dated rulings. The ledger is what a compacted or restarted super
# agent reads to know what it owns.
#
#   ledger --ledger <file> add --repo <owner/name> --number <n> --thread <id>
#          --worktree <path> --branch <name> [--kind ship|triage] [--machine <name>]
#          [--environment <id>] [--instance <id>] [--model <id>] [--effort <level>] [--area <path>]...
#   ledger --ledger <file> add --task <slug> --thread <id> [--worktree <path>] [--branch <name>]
#          [--repo <owner/name>] [--machine <name>] [--environment <id>] [--instance <id>]
#          [--model <id>] [--effort <level>] [--area <path>]... [--interactive]
#   ledger --ledger <file> add --launching <the add flags, less --thread and --worktree>
#   ledger --ledger <file> adopt <the same flags as add>
#   ledger --ledger <file> adopt --read <t3_thread_read file> [--task <slug>] [--repo <owner/name>] [--number <n>]
#          [--kind ship|triage] [--machine <name>] [--environment <id>] [--instance <id>]
#   ledger --ledger <file> get <key>
#   ledger --ledger <file> list [--open]
#   ledger --ledger <file> set <key> <field> <json>
#   ledger --ledger <file> rethread <key> --thread <id> --worktree <path>
#          --branch <name> [--kind ship|triage|task] [--environment <id>] [--instance <id>]
#          [--model <id>] [--effort <level>] [--area <path>]...
#   ledger --ledger <file> ruling <text> [--allow <call>]... [--repo <owner/name>]
#   ledger --ledger <file> pin <date> <text>
#   ledger --ledger <file> migrate-rulings <list.json>
#   ledger --ledger <file> allowed
#   ledger --ledger <file> scoped [--repo <owner/name>]
#   ledger --ledger <file> wait <key> --reason <text> [--order <n>] [--after <key>]
#   ledger --ledger <file> unwait <key>
#   ledger --ledger <file> need <key> --action <text> [--reason <word>]
#   ledger --ledger <file> pushed <key>
#   ledger --ledger <file> unneed <key>
#   ledger --ledger <file> limit <owner/name> --reviewer <name>
#   ledger --ledger <file> unlimit <owner/name>
#   ledger --ledger <file> take <key>
#   ledger --ledger <file> tell <key or thread id>
#   ledger --ledger <file> drop <key>
#   ledger --ledger <file> reset-stalls <key>
#   ledger --ledger <file> self [<thread id>]
#
# `self` records the super agent's own thread id (the argument, else
# `$T3CODE_THREAD_ID`) as `own_thread`: at the loop's start and each handover.
# A key is `<owner/name>#<number>`, or `task:<slug>` for a `task` entry. `--ledger` comes first and names the file,
# which a first `add` creates. `add` starts an entry at stage `launched`, stalls
# 0, observed null: `reconcile` fills `observed`, the baseline `watch` compares
# against, and `error`, the fault kind it last failed to read. `add --launching`
# is `launch` recording a ticket before its thread exists: stage `launching`,
# `thread` and `worktree` null, which `watch` and `reconcile` do not read (reconcile
# lists it in `launching`) and which still takes its machine's slot. `add` over an
# entry whose stage is `settled` or `closed` (a triaged ticket that now ships) or
# `launching` (`record` binding the thread) replaces it; over any other entry it refuses. `set` takes any
# field but the entry's identity (key, repo, number) and `stage`, which only
# `reconcile` moves (`add` and `rethread` start one at launched, `add --launching` at launching). `rethread` points a
# ticket's entry at a fresh thread and starts its tracking over (stage
# launched, stalls 0, no observed state), so the key stays one entry; `--environment` names the new thread's linked
# machine, and without it the entry is this machine's again. `--kind` and
# `--area` replace the stored value when given and leave it when omitted; use
# `add` over a finished triage entry, `rethread` for a thread that failed. A write
# holds the ledger's lock (`<ledger>.lock`) from its read to a temp file beside
# the ledger renamed onto it, so concurrent writes all land. A ruling is the owner's answer to a hold, dated. Each
# `--allow` is a call the answer lets a supervised thread make without a hold,
# and `allowed` lists them. `--repo` scopes a ruling to one repo so the gate-hold
# step-in can cite it for that repo's later holds, and `scoped` lists the rulings
# that have a repo (one repo's, compared without regard to case, with `--repo`).
# A ruling lapses 7 days after its date: `expires` holds the last day it is in
# force, and `list`, `allowed` and `scoped` leave a lapsed one out while the file
# keeps it. `pin <date> <text>` keeps one in force for good. `migrate-rulings`
# applies the owner-approved list once, a JSON array of {date, text, mark:
# pin|lapse|move, to}, `to` naming where a moved ruling now lives: a `pin` row
# pins its ruling, and a `lapse` row, a `move` row or a ruling with no
# `expires` the list leaves out gets yesterday as its `expires`.
# A ruling has no brief or machine scope: `--brief` and `--machine` are refused,
# and a ruling an older ledger marked brief-bound reads as a plain one. An entry's `--machine`
# is the fleet file's key for the machine the thread runs on (`local` means the
# machine the ledger is on), `--environment` the T3 environment id `place`
# returned for a linked machine (absent: this machine), which `reconcile` and
# `watch` read the entry's thread through, and each `--area` a path the ticket's work touches,
# which placement reads to run two tickets of one repo side by side. A ticket
# that could not be placed is `wait`ed: a row in `waiting` (no thread, no
# stage, never watched) that the morning report lists, and that `add` or
# `unwait` removes. The waiting list is also the owner's queue: a row takes an
# `--order` (a whole number of up to 9 digits, lowest first, 0 allowed; rows with none follow the
# ordered ones, oldest first) and an `--after <key>` blocker, another ticket that
# must merge first, which `reconcile` reads into its `ready` rows. A repeat
# `wait` keeps the order and blocker it is not given anew. `--kind` is the owner skill the thread runs, `ship` (the
# default) or `triage`: a `triage` entry has no PR, and `reconcile` settles it
# when its run has completed and the issue carries neither `needs-triage` nor `needs-info`.
# A `task` entry (`--task <slug>`, kind `task`) is any other thread the super agent
# launched (a grill, a deploy, a review): its key needs no issue number, `repo` and
# `number` are null unless `--repo` is given (so a remote task's PR is found by its
# `--branch`), and `reconcile` closes it on its thread's rest, never on an issue's or
# a PR's state. `adopt` takes `add`'s flags and records a thread someone else launched
# (`adopted` true, kind `task` unless `--repo` and `--number` name a ticket); the
# watcher and `reconcile` treat it like a launched one. `--interactive` marks a task
# whose skill waits on the owner by design (a grill): `reconcile` counts it no stall
# and does not settle it on its rest, so it leaves on `drop`.
# `take` is the owner taking an open entry's thread ("I'll take <thread>"): the entry
# is `owner_run` and its open needs are cleared. It keeps its stage, so it still takes
# its machine's slot, and `reconcile` and `watch` count it no stall and raise no step-in
# for it; a ticket's entry settles on its PR merging or its issue closing, read from
# GitHub alone, with no cleanup owed, and a task's stays until `drop` or a second
# `adopt` of its thread, which gives it back: the mark and the `observed` baseline go,
# so the next `reconcile` watches from the thread's state then, its runs since the
# take counting no stall. `reconcile` lists one `owner-run` escalate row after 3 days.
# `tell` is the owner's "Tell <thread> X": one send into that entry's thread (or a
# thread id the ledger need not hold) gets past the call guard (`call-guard.sh`), and a
# dated ruling records it. `adopt --read` is "Watch <thread>": the thread's first page,
# saved from `t3_thread_read` with `afterPosition: -1`, fills the entry (worktree,
# branch, first pull request, and from the first user message `/ship-run <n>` or
# `/triage <n>` the kind and number; `--task` for any other thread; the repo from
# `--repo`, else the worktree's origin remote) and starts its clock then:
# `launched_at` and `held_since` are now. An open entry that already holds the thread
# is the entry returned (`existing` true), given back when owner-run and no longer
# steered; a ship adoption with no claim comment of this super agent's gets one
# (`claim.sh`, on the entry's `--machine`). `drop` removes an
# entry of any stage. `reset-stalls` zeroes an open entry's stall count and restarts
# its stall window, and records a dated ruling naming the key and the count it replaced.
# A `need` is something only the owner can settle: one row in `needs` per key
# (the entry, or a waiting ticket), its one action, `since` when and whether its
# push went out. A repeat with the same action keeps `since` and `pushed`, a new
# action is a new need. `--reason` names the cause it answers: only that
# `escalate` row stays silent for it. `pushed` marks the push sent, `unneed` clears the need;
# `status` reads the rows. `--instance` is the T3 provider instance the thread
# launched on (route's `instance_id`), which `status` names on the Running row. A
# `limit` records that a repo's hosted reviewer answered a review request with a
# usage-limit notice: one row in `review_limits` per repo, its reviewer and
# `since`, the time of the first notice (`SA_NOW`, an epoch, pins the clock for
# tests). A repeat keeps the first row, so the time is the first notice's, and
# `status` says that repo's batch is merging on the fallback reviewer only while
# the row is open. `unlimit` clears it once a later run records that reviewer as
# landed, or the owner says so.
#
# stdout: `add` {ledger, key, entry}, `adopt` also {existing: true} for a thread an entry already held; `get` the entry; `list` {ledger, entries,
#         rulings}, `entries` an array of entries (`--open` leaves out settled
#         and closed ones); `set` {key, field, value}; `rethread` {ledger, key, entry}; `ruling` {ruling:
#         {date, text, allow, repo, expires, pinned}}; `pin` {pinned:
#         [ruling]}; `migrate-rulings` {pinned: [{date, text}], lapsed: [{date,
#         text}], moved: [{date, text, to}]}; `allowed` {allowed: [{date, call, line}]};
#         `scoped` {scoped: [{date, text, repo}]}; `wait`
#         {waiting: {key, repo, number, reason, since, order, after}}; `unwait` {key,
#         removed}; `need` {need: {key, action, since, pushed}}; `pushed`
#         {need}; `unneed` {key, removed}; `limit` {limit: {repo, reviewer,
#         since}}; `unlimit` {repo, removed}; `take` {key, owner_run}; `tell` {thread, at, ruling};
#         `drop` {key, removed}; `reset-stalls` {key, stalls, ruling}; `self` {own_thread};
#         `list` also holds `waiting`,
#         `needs` and `review_limits`; any failure {error}
# exit: 0 ok · 1 the key is already in, or not in, the ledger, `stage`, an
#       identity field, an entry that ended (`take`, `reset-stalls`), a key `tell` does not
#       know, a ruling that `pin` or a migration row names
#       but the ledger lacks, or a second `migrate-rulings` · 2 usage, a value
#       that is not JSON, an unreadable or wrong-shaped ledger, or a write that
#       failed
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh" || { printf '{"error":"cannot source _lib.sh"}\n'; exit 2; }

usage='usage: ledger --ledger <file> add (--repo <owner/name> --number <n> --worktree <path> --branch <name> [--kind ship|triage] | --task <slug> [--worktree <path>] [--branch <name>] [--repo <owner/name>]) --thread <id> [--machine <name>] [--environment <id>] [--instance <id>] [--model <id>] [--effort <level>] [--area <path>]... [--interactive] | adopt (--read <t3_thread_read file> | --thread <id>) [--repo <owner/name>] [--number <n>] [--worktree <path>] [--branch <name>] [--kind ship|triage] [--task <slug>] [--machine <name>] [--environment <id>] [--instance <id>] [--model <id>] [--effort <level>] [--area <path>]... [--interactive] | add --launching <the add flags, less --thread and --worktree> | get <key> | list [--open] | set <key> <field> <json> | rethread <key> --thread <id> [--worktree <path>] [--branch <name>] [--kind ship|triage|task] [--environment <id>] [--instance <id>] [--model <id>] [--effort <level>] [--area <path>]... | ruling <text> [--allow <call>]... [--repo <owner/name>] | pin <date> <text> | migrate-rulings <list.json> | allowed | scoped [--repo <owner/name>] | wait <key> --reason <text> [--order <n>] [--after <key>] | unwait <key> | need <key> --action <text> [--reason <word>] | pushed <key> | unneed <key> | limit <owner/name> --reviewer <name> | unlimit <owner/name> | take <key> | tell <key or thread id> | drop <key> | reset-stalls <key> | self [<thread id>]'
sa_help "$usage" "$@"
[ "${1:-}" = --ledger ] || sa_tooling "$usage"
sa_flag_value "$usage" "${2:-}"; ledger=$2; shift 2
cmd=${1:-}; [ $# -gt 0 ] && shift

case $cmd in
  add|adopt)
    source "$(dirname "${BASH_SOURCE[0]}")/ledger.d/add.sh" && ledger_add "$@" ;;
  get)
    [ $# -eq 1 ] || sa_tooling "$usage"
    sa_read "$ledger"
    key=$(sa_key "$doc" "$1")
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$1 is not in the ledger"
    jq -c --arg k "$key" '.entries[$k]' <<<"$doc" ;;
  list)
    open=false
    case ${1:-} in --open) open=true; shift ;; esac
    [ $# -eq 0 ] || sa_tooling "$usage"
    sa_read "$ledger"
    jq -c --arg l "$ledger" --argjson open "$open" --arg today "$(sa_today)" "$sa_jq_open$sa_jq_waiting$sa_jq_live"'{ledger: $l, entries: [.entries[] | select(($open | not) or is_open)], rulings: [.rulings[] | select(live($today))], waiting: waiting_list, needs: (.needs // []), review_limits: (.review_limits // [])}' <<<"$doc" ;;
  set)
    [ $# -eq 3 ] || sa_tooling "$usage"
    key=$1 field=$2
    value=$(jq -c . <<<"$3" 2>/dev/null) && [ -n "$value" ] || sa_tooling "the value is not JSON: $3"
    case $field in
      key|repo|number) sa_fail "$field is the entry's identity and cannot be set" ;;
      stage) sa_fail "stage is moved by reconcile only (add starts it at launched or launching, rethread at launched)" ;;
    esac
    sa_lock "$ledger"; sa_read "$ledger"
    key=$(sa_key "$doc" "$key")
    jq -e --arg k "$key" '.entries[$k]' <<<"$doc" >/dev/null || sa_fail "$key is not in the ledger"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    sa_update "$ledger" '.entries[$k][$f] = $v | .entries[$k].updated_at = $now' \
      --arg k "$key" --arg f "$field" --argjson v "$value" --arg now "$now"
    jq -cn --arg k "$key" --arg f "$field" --argjson v "$value" '{key: $k, field: $f, value: $v}' ;;
  rethread)
    source "$(dirname "${BASH_SOURCE[0]}")/ledger.d/rethread.sh" && ledger_rethread "$@" ;;
  wait|unwait)
    source "$(dirname "${BASH_SOURCE[0]}")/ledger.d/waiting.sh" && ledger_waiting "$cmd" "$@" ;;
  ruling|allowed|scoped|pin|migrate-rulings)
    source "$(dirname "${BASH_SOURCE[0]}")/ledger.d/rulings.sh" && ledger_rulings "$cmd" "$@" ;;
  need|pushed|unneed|limit|unlimit|take|tell|drop|reset-stalls|self)
    source "$(dirname "${BASH_SOURCE[0]}")/ledger.d/owner.sh" && ledger_owner "$cmd" "$@" ;;
  *) sa_tooling "$usage" ;;
esac
