# Schedules and lessons

## Contents

- [Schedules](#schedules)
- [A recurring find](#a-recurring-find)
- [A cross-repo lesson](#a-cross-repo-lesson)

`scripts/` is under this skill's base directory; the fleet file is defined in
SKILL.md's `## Setup`.

## Schedules

Offer these once setup has written the fleet file, and create one only after
the owner's yes: a schedule runs unattended, so the owner chooses each one.

1. Run `scripts/schedules.sh --fleet <fleet>` (`--morning HH:MM` and
   `--retro-day 0-6` when the owner named a time). It proposes `morning`, the
   ledger report on each day of the fleet file's `work_week`, and one weekly
   `retro` row per active repo, on the work week's last day unless
   `--retro-day` names another.
2. Show the proposal: each title, schedule and prompt.
3. Ask with AskUserQuestion, yes first as the recommendation, one option per
   schedule or a single yes for all.
4. On a yes, run `list_scheduled_tasks` and skip any schedule that already
   exists for the same thread or project, so a re-offer never doubles one.
   Create each remaining one with `schedule_task`, its `schedule` and `prompt`
   from the proposal:
   - `morning` (`bind` `this-thread`): `bindToCurrentThread` true;
   - each `retro` (`bind` `repo-project`): `projectId` the repo's T3 project
     from `t3_project_list`, `bindToCurrentThread` false, prompt
     `/retro-run`.
5. On a no, or no answer, create nothing. Delete a schedule only on the
   owner's word.

## A recurring find

A **recurring find** is one class of mistake or gap seen in two or more
tickets: supervised threads' PRs, reconcile stalls, hard findings. Fix the
class once, upstream of the tickets, since a per-ticket fix lets the next
ticket hit it again.

1. File one issue for the class in the repo it hits, through that repo's owner
   skill route, so `/triage` picks it up. Finds that share a file go in that
   one issue.
2. Order it before the work it would hit: launch it first, or record a
   blocking edge on each ticket it blocks.
3. Hold each dependent ticket with `ledger.sh wait <key> --reason <text>`
   until the issue's PR merges, then `ledger.sh unwait <key>` and launch it.

## A cross-repo lesson

A lesson that holds in more than one repo belongs in the owner's global rules,
so every repo's runs inherit it.

1. Propose it as a Needs you escalation: the proposed rule text and its
   evidence, the tickets or PRs that showed it.
2. On the owner's yes, write it in the owner's own rules by the owner's
   method. On a no, drop it.
3. Keep it out of a repo's public text when it would name private things.
   Lessons go to the owner's rules alone, a wiki never.
