# The storyboard

The **storyboard** is where the person meets the video before the expensive
render, and approves its look once. It is a page with one tab per chapter
showing the chapter's status; every scene a card of three
stills (in, key, out) rendered from the authored scene, its timecode, its
narration and short notes, with a comment box; one comment for the whole look;
the chapter plan as a table, with no stop of its own; and on chapter 1's board
the three directions as one frame each. In a video in chapters the person
approves on chapter 1's board alone; a later chapter shows in the plan and its
tab while its author works, and its cards appear on the board built once it
replies. The page is a claude.ai artifact, or a
local file when the session has no artifact tools.
[board/board-data.md](../board/board-data.md) holds the board and answers
documents. Each version of the storyboard is a **board**, numbered from 1.
`<skill>` and `<run>` are as in [SKILL.md](../SKILL.md), and `board` below is
`node <skill>/scripts/board/board.mjs <run>`.

1. **Inputs.** Write `<run>/storyboard.json`: the video's `title`, the
   chapter's `focus` in one line (in chapters, each chapter's comes from the
   plan), `directions` (`list` of the three from
   `DIRECTIONS.md`, each `id`, `name` and `kind`; the `recommended` id; the
   `picked` id, the one the scenes are authored in), and `scenes`, keyed by
   scene id, each its `title` and `notes` (what the card's stills cannot say:
   what moves on which word, the sound, the metaphor's limit):

   ```json
   {"title": "...", "focus": "...",
    "directions": {"recommended": "switch", "picked": "switch",
                   "list": [{"id": "switch", "name": "...", "kind": "..."}]},
    "scenes": {"hook": {"title": "...", "notes": "..."}}}
   ```

   For each direction other than the picked one, author
   `<run>/directions/<id>.html`: chapter 1's first scene at its key moment in
   that direction's look, one composition, written the way a scene file is,
   `data-composition-id` its direction id, its own styles (the kit is not
   loaded), settled by 1 s.
2. **Surface.** The page needs the `Artifact`, `ArtifactData` and
   `ArtifactComments` tools. With any of them missing, or when the person says
   the page cannot reach its database, the board is **local** for the rest of
   the run.
3. **Build.** `board build`. It renders the stills and the direction frames,
   then prints `board: <n> -> board/storyboard.html (...)` and `board: files
   board/files.json`. Exit 1 names what to fix first. `board: <ids> changed,
   but board <k>'s comments named only <ids>: re-author only those scenes`
   (board `<k>` the latest board answered) means you changed a scene nobody
   commented on, the kit, `over.html` or an
   asset another scene may use (`<ids>` then holds `the kit`, `over.html` or
   `assets/<file>`): put back each one it names as it was, and build again. A
   new asset, or a later chapter's newly authored scene, is fine.
4. **Show it.** Published: `Artifact` publish with `file_path`
   `<run>/board/storyboard.html` and `files` the map `board/files.json` holds;
   on the first board add `capabilities` `{"db": {}, "user": {}, "comments":
   {}}`, `icon` `video` and a one-sentence `description`. On later boards
   publish the same `file_path` with that board's `files` map (its stills are
   new files), and no `capabilities` or `icon`, which keeps the URL. A Submit
   wakes this session only while the artifact's watch shows auto-replies armed;
   when the publish result's subscription line leaves that in doubt, check
   with `ArtifactComments` `watch` and no `url`, and unarmed, tell the person
   to type `submitted` here after each Submit. A refused publish makes the
   board local. Local: say the board is `<run>/board/storyboard.html`, opened
   in a browser, and that its Submit shows an answers text to paste back here.
   Then print the link or the path and `Board <n> posted.`, and end the turn.
5. **Read a Submit.** The Submit comment, a typed `submitted` or a pasted
   answers text starts the next turn. Published: `ArtifactData` `get` with
   the `url` the first publish returned, collection `answers`, doc id
   `board-<n>`, `out_dir` `<run>/board/inbox`, and `board apply` the file it
   saved. With no such document, or local, write the comment's or the pasted
   text to `<run>/board/inbox/answers.txt` and apply that. A comment carrying
   no answers is the person talking: answer it here. Resolve the Submit thread
   (`ArtifactComments` `resolve`, the `url` and its thread id) once the next
   board is posted, or once the gates begin.
6. **Act on it.** `board apply` prints what the answers ask; act on every line
   it prints:
   - `board: approved`: go on to SKILL.md step 12.
   - `board: these answers approve nothing and comment on nothing`: tell the
     person, and end the turn with the board still posted.
   - `board: direction <id>`: set `picked` to it in `storyboard.json` and write
     the new pick into `DIRECTIONS.md`, author `directions/<old>.html` for the
     direction it replaces, write `SPEC.md` and the kit again in the new look,
     and re-author every scene in it.
   - `board: look: <text>`: change what the comment asks of the whole look
     (`SPEC.md`, the kit, and each scene it reaches).
   - `board: redo <id>: <note>`: re-author that scene, and only that scene,
     from its note. The next build refuses a change to any other scene (its
     file or its narration), the kit, `over.html` or an asset it may use.

   Then snapshot what changed as the stills review does (SKILL.md step 10),
   and build again from step 3: the board comes back.
