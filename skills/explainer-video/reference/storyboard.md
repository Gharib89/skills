# The storyboard

The **storyboard** is the run's one stop for the user: one card per scene with
its narration, a still, its voiced length and style notes, beside the brief
and the source pack, playable as an **animatic** (each still over its scene's
real narration, in order). The user approves or revises each card, may edit
its narration in place, and presses Submit. Its page is
[storyboard/page.html](../storyboard/page.html), fixed and tested, and
[storyboard/board-data.md](../storyboard/board-data.md) is the contract between
the page and `<skill>/scripts/storyboard/board.mjs`: each **board version** is
one document, and a revision, a gate stop and the delivery each post a new
one. `board` below is `node <skill>/scripts/storyboard/board.mjs
explainers/<slug>`. Stage and step names (Script, Voice, Render) are
SKILL.md's.

1. **Stills.** `node <skill>/scripts/render/render.mjs explainers/<slug>
   --stills` renders one settled still per scene and nothing else, printing
   `render: stills <hit>/<n> cached`; a scene unchanged since its last still is
   a cache hit. A failure reads as under Render step 7.
2. **Surface.** The page needs the `Artifact`, `ArtifactData` and
   `ArtifactComments` tools. With any of them missing, or when the user says
   the page cannot reach its database, the board is **local** for the rest of
   the run: skip to step 4, and say in one line that the board is
   `explainers/<slug>/storyboard.html`, opened in a browser, and that the user
   pastes its answers text back here.
3. **Publish, once per run.** `board page` writes `board/page.html`, the page
   with the video's title. Publish that file as a new artifact:
   `capabilities` `{"db": {}, "user": {}, "comments": {}, "assets": {}}`, `icon`
   `video`, a one-sentence `description`. Refused: the board is local (step 2).
   Never publish it again: every later change is a board version. Record its
   URL with `board page <url>`, which keeps it in `manifest.json`. A Submit
   wakes this session only while the artifact's watch shows auto-replies armed;
   when the publish result's subscription line leaves that in doubt, check with
   `ArtifactComments` `watch` and no `url`. Unarmed, tell the user to type
   `submitted` here after each Submit.
4. **Build.** `board build`, or `board build --local` on a local board (a
   page recorded earlier would otherwise ask for uploads). Exit 1 with
   `board: no <file>` or `no still` names the stage to run first. On a
   published page it first lists
   `board: upload <path> (<size>)` per still, narration or clip the page does
   not hold yet: upload them with `Artifact` publishes of up to 25 files each,
   `url` the page, `asset: true` and `file_paths` each path prefixed with
   `explainers/<slug>/`, record each with `board asset <path>=<url> ...`,
   `<path>` as `board` printed it and the `url` exactly as the upload result
   gives it, and build again. `<path> is <n> MB, over the 15 MB asset cap`
   means that file cannot go on the page: relay it. On exit 0 it prints `board
   <n>: <kind>, <k> card(s), <o> to answer -> board/<n>.json`. Published: write
   that file with `ArtifactData` `set`, collection `boards`, doc id `<n>`,
   `file_path` the file. Then print the page link, or the local file's path,
   and `Board <n> posted. Cards to answer: <o>.`, and end the turn.
5. **Read a Submit.** The Submit comment on the page, a `submitted` typed
   here, or a pasted answers text, starts the next turn. Published:
   `ArtifactData` `get` collection `answers`, doc id `board-<n>`, with `out_dir`
   `explainers/<slug>/board/inbox`, and run `board apply` on the file it saved.
   With no such document, or local, write the comment's or the pasted text to
   `explainers/<slug>/board/inbox/answers.txt` and apply that. A comment
   carrying no answers is the user talking: answer it here. Resolve the Submit
   thread once the next version is posted, or once the run goes on to Render.
6. **Apply.** `board apply <file>` writes an edited narration into the scene
   file, touching only that scene, and prints one `board <id>: approve` or
   `revise: <note>` line per card. `board: approved`: go on to Render. `board:
   redo <ids>`: first run `brief.mjs` with the `; brief` arguments it lists, if
   any, and follow its redo line; then, for each card revised with a note,
   change that scene in `script.md` as the note asks (a `revise: no note` line
   without `, narration edited` names nothing to change: ask the user what to
   change before rebuilding); then Script steps 2 to 6,
   Voice and step 1 again, each reusing its cache for every scene not changed,
   and build the next version (step 4). A note asking for a claim the sources
   do not support follows the Script stage's support stop. `answers for board
   <a>, the latest is board <b>` or `cut to fit`: read the latest version's
   answers document instead; with none, ask the user to copy the answers the
   page shows and paste them here. Any other `board:` refusal: relay it as
   printed and ask the user to copy the answers again.
7. **Gate stop.** On Render's `stop`, build and post the next version
   (step 4): it carries a banner with each red gate's line and reopens every
   card the gates' findings name. A finding that names no scene (`loudness`,
   `captions`) reopens no card: relay its line and `gates.md`. End the
   turn; the revisions come back through step 5.
8. **After delivery**, build once more (step 4): it cuts each scene's stretch of
   the delivered MP4 into a clip under 15 MB, and its `delivered` version plays
   them on the cards. Post it as in step 4, then report Render's last line and
   the videos-folder path.
