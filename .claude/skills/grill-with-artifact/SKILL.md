---
name: grill-with-artifact
description: "Grill a plan or design on a private artifact page: each grilling round arrives as question cards you answer and Submit, and the glossary and ADRs are written as answers settle. Runs in the terminal where artifacts are unavailable."
disable-model-invocation: true
metadata:
  version: 0.1.0
---

# grill-with-artifact

The same grilling as `grill-with-docs`, with a page as the surface. Call the
Skill tool twice, for `grilling` and `domain-modeling`: they own the design
tree, the frontier, "facts are your job" and every glossary and ADR write. This
skill replaces only two things in them: how a **grilling round** is shown (a
round document on the page, never the terminal format `grilling` gives) and how
the answers come back (a Submit on the page).

The page is [page.html](page.html), fixed and tested: a session fills its title
and publishes it once. From then on every grilling round is a document in the
page's database, and the page renders it live. [round-data.md](round-data.md)
is the contract between the two: read it before writing round 1, and hold every
document you write to its field table and its figure style contract.

## 1 · Pick the surface

The page needs the `Artifact`, `ArtifactData` and `ArtifactComments` tools.
With any of them missing, or when the publish in step 2 is refused, print one
line, `No artifact surface here, so this session runs in the terminal.`, and
run the whole session as `grilling` and `domain-modeling` describe. Skip the
rest of this file.

**Done when:** the session is on the page, or the one line is printed and the
terminal format runs.

## 2 · Publish the page

1. Settle the topic with the human in a few words: it names the page in their
   artifact gallery, so it tells this session apart from every other.
2. Copy `page.html` into your scratchpad as `grill-<topic-slug>/page.html` and
   replace its one `{{TOPIC}}` with the topic, HTML-escaped (`&`, `<`, `>`,
   `"`).
3. Publish that file as a new artifact: `capabilities`
   `{"db": {}, "user": {}, "comments": {}}`, `icon` `question`, and a one
   sentence `description` naming what is being grilled. Each session gets its
   own artifact; never publish over another session's page.
4. Read the publish result's subscription line. The Submit wake reaches you
   only while the artifact's watch shows auto-replies armed; when the line
   leaves that in doubt, check with `ArtifactComments` `watch` and no `url`.
5. Print the page link, and whether the wake is armed. Unarmed, add that the
   human types `submitted` in the terminal after each Submit.

**Done when:** the link is printed, and the terminal says whether Submit wakes
the session.

## 3 · Post a grilling round

1. Compute the frontier as `grilling` says. Every question gets two to four
   options, a `recommended` option and a `why`. The page adds Other and Defer
   itself, and preselects nothing.
2. Draw the design tree as `treeSvg`: every decision as a node in its state
   (`n-settled`, `n-open`, `n-blocked`, `n-deferred`), each open node carrying
   `data-q` for its question, and `hot` on the edge or node with the most riding
   on it, named in `treeCaption`.
3. Give a question a `figureSvg` only where a mechanism or a comparison is
   faster seen than read. The first time one earns a figure, load
   `artifact-diagramming` through the Skill tool, and draw it with the figure
   style contract's classes, which win over any colours that skill suggests.
   With `artifact-diagramming` not installed, the round goes out with no
   figures and stays on the page.
4. From round 2 on, fill `settled` with one entry per question the previous
   round asked, and `docsWritten` with every glossary term and ADR written from
   its answers.
5. Write the round with `ArtifactData` `set`, collection `rounds`, doc id the
   round number. A posted round is final: the next round is a new document,
   and the page is never republished.
6. Print one status line, `Round <n> posted: <k> questions.`, and end the turn.
   The questions live on the page only, so the human answers one copy.

**Done when:** `rounds/<n>` is written and the status line is printed.

## 4 · Read a Submit

The Submit comment is a **doorbell**: the one page action that starts a turn in
this session. It arrives as a comment on the watched artifact, sent to Claude.
A `submitted` typed in the terminal rings the same bell.

1. Read `answers/round-<n>` with `ArtifactData` `get`. With no such document,
   take the answers from the comment's text, which carries them too; a pasted
   answers text in the terminal is the same text. A comment carrying no answers
   is the human talking: answer it in the terminal and keep waiting.
2. Apply each answer as `grilling` and `domain-modeling` say, writing any term
   or ADR it settles now, in the repo.
3. **Defer** puts the question back in the next round with `carriedFrom`
   reason `deferred`. **Reopen** puts a settled question back with reason
   `reopened` and its answer as `earlier`; recompute which later decisions
   rested on it, and carry each of those back too, or mark it blocked in the
   tree.
4. Post the next grilling round (step 3), then `ArtifactComments` `resolve` the
   Submit thread, so an open thread always means still working. The platform's
   own reply in the thread is the receipt; add none of your own.

**Done when:** every answer is applied, the next round is posted, and the
Submit thread is resolved.

## 5 · Close

When the frontier is empty, post a closing round: `kind` `closing`, with
`summary` holding every decision under a few headings. The page shows Confirm
and Not yet. **Not yet** comes with a comment saying what is missing: grill it
as a new frontier from step 3. **Confirm** ends the session: print one line
saying so, then resolve its thread.

Any outward-facing step that follows (filing issues, writing a spec) waits for
the Confirm. A next command the Skill tool cannot run, such as `/to-spec`, is
named for the human to type.

**Done when:** the human pressed Confirm and its thread is resolved.
