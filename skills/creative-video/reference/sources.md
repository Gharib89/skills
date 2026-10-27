# Sources

The source stage reads each source into the **source pack** in the run folder
`creative-videos/<slug>/`: a verbatim **snapshot** per source, the
**excerpts** a script may cite, each the source's own words at a **locator**
(`page 4`, `§ Install`, `src/app.js:12-14`), and the **outline**. A source is
a git repo folder (`.` for this repo), a web page URL, or a `.pdf`, `.md`,
`.txt`, `.html`, `.docx` or `.pptx` file. Subagents read the snapshots; only
the outline enters this conversation, so a large repo does not crowd out the
work. A concept with no source is a topic.

0. **Topic.** Given a topic and no source, dispatch one subagent with
   `<skill>/agents/researcher.md` as its prompt, `{topic}` the topic,
   `{focus}` what the video teaches, `{audience}` who it is for, `{avoid}`
   none. Its reply, 3 to 8 page URLs, is the sources: snapshot them with
   `--topic "<topic>"`. A page the snapshot cannot read: dispatch it once more
   with `{avoid}` every page refused so far, and snapshot its new list. On
   `too few`, or a second refusal, relay it and ask the person for a source.
1. **Snapshot.** `node <skill>/scripts/source/snapshot.mjs
   creative-videos/<slug> [--minutes <n>] [--topic "<topic>"] <source>...`,
   `--minutes` the video's length. It replaces `snapshots/` whole, so every
   reader runs again after it. It prints `source <id>: <kind> · <n> <unit> ·
   <source>` per source, a repo's followed by `withheld <id>/<path>: <why>`
   for each file withheld for a secret (relay these), then the excerpt budget
   and each source's share.
2. **On exit 1**, relay each `source <source>: <why>` line. On `source: <row>
   is not installed`, run setup, then snapshot again. A scanned PDF or a
   folder outside git: ask for the source in another form, or to drop it.
3. **Read.** Dispatch one subagent per source, at most 20 at once, each with
   `<skill>/agents/source-reader.md` as its prompt, placeholders from that
   source's entry in `snapshots/sources.json` (`{id}`, `{kind}`, `{source}`,
   `{snapshot}`, `{share}`), `{run}` the run folder, `{skill}` this skill's
   folder, `{focus}` what the video teaches. Read no snapshot or draft here.
4. **Pack.** `node <skill>/scripts/source/pack.mjs creative-videos/<slug>`
   numbers the excerpts `ex-1`, `ex-2`, ... and writes `excerpts.json` and
   `outline.md`. On exit 1, send each `pack <id>: ...` line to that source's
   reader to fix, then pack again.
5. **Outline.** Read `outline.md`: each source's summary, each excerpt's id,
   locator and note. Every factual sentence of the script comes from an
   excerpt you can name.
6. **Still standing.** For each source a factual sentence leans on (a study, a
   benchmark, a release note), search for a later update, erratum,
   retraction or newer version by its authors. A source that was updated or
   withdrawn is cited at its current word, or its fact is dropped; say which in
   `DELIVERY.md`.
