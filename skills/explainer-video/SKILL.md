---
name: explainer-video
description: >-
  Make a narrated explainer video from a repo, a document, a web page or a
  topic. Use when the user asks for an explainer video, or for its tools to
  be checked or installed (`/explainer-video setup`).
metadata:
  version: 0.1.0
---

# explainer-video

An **explainer video** is a narrated video, one to five minutes by default,
made from one or more sources. This version carries only the first stage every
run starts with, **setup**: the video stages after it are not in this version.
Asked for a video, say so in one line and offer `setup` instead.

## Setup

`/explainer-video setup` runs the check and the install with no video, so the
tools are in place before a deadline. Setup writes to two per-user folders: the
**tool cache**, holding the npm packages and Chrome under the hash of this
skill's lockfile, and the **font store**, holding fonts by family and version.
An install in the tool cache for another lockfile hash that no run has used for
30 days is **stale**. Run the script by the skill's own path, `<skill>` below
being the folder this file is in:

1. **Check.** `node <skill>/scripts/setup.mjs check`, adding `--all` when the
   user asked for every opt-in row too. Exit 0 means every row is present and
   nothing is stale: say so and stop.
2. **One yes.** Show the table as printed, then ask once for the whole table,
   naming the total it prints: one yes installs every missing row and removes
   every stale install. Run install only after the yes. When every missing row
   is a system package and nothing is stale, skip the question and go to step
   4.
3. **Install.** `node <skill>/scripts/setup.mjs install`, with the same
   `--all`. It installs into the tool cache and the font store, removes the
   stale installs, then prints the table again.
4. **Report.** Show the latest table. A `missing` system package (ffmpeg, or
   `uv` beside an opt-in Python row) is one the skill never installs: relay its
   install lines from the output, ask the user to run the one for their OS,
   then check again. A `refused` or `failed` row: relay the reason as printed.

To remove the tools, the user deletes the folders the `writes to` column names.
Setup deletes inside those folders alone, and only after the yes: the stale
installs, and what an earlier install of a missing row left half done.
