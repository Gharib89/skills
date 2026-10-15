---
name: explainer-video
description: >-
  Make a narrated explainer video from a repo, a document, a web page or a
  topic. Use when the user asks for an explainer video or runs
  /explainer-video, including `/explainer-video setup`, which checks and
  installs the tools a video needs.
metadata:
  version: 0.1.0
---

# explainer-video

An **explainer video** is a narrated video, one to five minutes by default,
made from one or more sources. This version carries the first stage every run
starts with, **setup**: the video stages after it (source, brief, script,
storyboard, voice, score, render, gates, delivery) have not landed yet. Asked
for a video, say so in one line and offer `setup` instead.

## Setup

`/explainer-video setup` runs the check and the install with no video, so the
tools are in place before a deadline. Every script here is Node, never bash,
because the skill runs natively on Linux, macOS and Windows. Run them with the
skill's own path, `<skill>` below being the folder this file is in:

1. **Check.** `node <skill>/scripts/setup.mjs check`, adding `--all` when the
   user asked for every opt-in row too. It prints a table: row, needed by,
   status, size on disk, licence, and where it writes. Exit 0 means every row
   is present: say so and stop.
2. **One yes.** Show the table as printed, then ask once, naming the total it
   prints: one yes installs every missing row and removes every `stale` one.
   Never ask row by row, and never install before the yes.
3. **Install.** `node <skill>/scripts/setup.mjs install`, with the same
   `--all`. It installs into the user's tool cache and font store, removes the
   stale installs, then prints the table again.
4. **Report.** Show the second table. A `missing` system package (ffmpeg, or
   `uv` beside an opt-in Python row) is never installed by the skill: relay its
   apt, brew and winget lines from the output and ask the user to run the one
   for their OS, then check again. A `refused` or `failed` row: relay the
   reason as printed.

Removing the tools is deleting the tool cache, whose path the `writes to`
column shows: the skill prints it and deletes nothing itself.
