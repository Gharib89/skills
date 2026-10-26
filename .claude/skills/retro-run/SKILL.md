---
name: retro-run
description: >-
  Report the classes of mistake that recurred across two or more of the week's
  merged PRs, read from the git host alone. Use when the user or a scheduled
  routine asks for a retro run, or to find what keeps going wrong across
  recent PRs.
argument-hint: "[--days <n>]"
metadata:
  version: 0.1.0
---

# retro-run

One **retro run**: read the git host's record of a window of merged PRs, find
the classes of mistake that recurred in two or more of them and were never
filed before, and report them. It changes no code or instructions, and writes
nothing to the host.

## The script

`scripts/retro.sh` under this skill's base directory answers `--help` with its
flags and the JSON it prints. Run it from the repository's checkout:

```sh
<base directory>/scripts/retro.sh candidates [--days <n>]
```

`--days` is the window, seven by default; pass the argument the run was given.
It prints the PRs merged in the window that carry a signal, each with its
number, title, closing issues and the signal text, and under `filed` the class
keys of every earlier issue labelled `retro`, open or closed. Exit 1 or 2:
report its `error` as the run's last line and stop.

## The run

1. **Group the signals into classes.** A class is the shared cause of a
   mistake, not one PR's symptom: two threads about different unpaged list
   reads are one class, `unpaged-list-read`, while a thread and a deviation
   about unrelated files are two. Give each class a kebab-case key and a
   one-line summary. A signal that names no mistake (a clean round, a thread
   that was declined as wrong) joins no class.
2. **Keep only classes seen in two or more PRs.** Count distinct PR numbers: a
   class seen twice in one PR is seen once. A one-off was handled in its own
   review round, and reporting it again is noise.
3. **Leave out every class already filed.** Drop a class whose key, or whose
   meaning, matches one under `filed`, open or closed: an accepted lesson is
   being built, and a rejected one stays rejected.
4. **Report.** One entry per class left: its key, its summary and the PRs it
   was seen in, as `#<n>` links. Then the last line, alone:

   - `retro-run <version>: <k> recurring classes in <m> merged PRs: <key> (#<n>, #<n>), ...`
   - or `retro-run <version>: nothing new recurred in <m> merged PRs.`

   `<version>` is `metadata.version` above, and `<m>` is the script's `merged`.
