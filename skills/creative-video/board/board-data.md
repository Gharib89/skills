# Board data

The one contract between a run and [page.html](page.html), the storyboard
page. `scripts/board/board.mjs build` writes one **board document** per board
version; the page writes one **answers document** per Submit. `apply` reads
the answers.

## Contents

- [Documents](#documents)
- [Fields](#fields)
- [Answers document](#answers-document)
- [Answers text](#answers-text)
- [Who reads what](#who-reads-what)

## Documents

| Document | Written by | When |
|---|---|---|
| `board/<n>.json` | `build` | once per board version, never rewritten |
| `board/storyboard.html` | `build` | with each board: the page with that board embedded |
| `board/answers-<n>.json` | `apply` | the normalized answers of board `<n>` |
| database `answers/board-<n>` | the page, on Submit | once per Submit of version `<n>`, on the artifact page only |

The page is never fed boards through a database: a new board is the same
`storyboard.html` published again, which keeps the artifact's URL.

## Fields

`board.` is the board document; `[]` is an array element. The page reads
nothing outside this table, and every field below is in every board.

| Path | Type | Meaning |
|---|---|---|
| `board.version` | number | The board's number, the same as its file name. |
| `board.title` | string | The video's title, from `storyboard.json`. |
| `board.language` | string | The narration's language code, from `script.json`. |
| `board.length` | string | The video's length, `m:ss`. |
| `board.chapters` | array | One entry per chapter of the plan (`script.json`'s `chapters`, `timeline.json`'s); a video with none has one, titled as the video. |
| `board.chapters[].n` | number | The chapter's number, from 1. |
| `board.chapters[].title` | string | The chapter's title. |
| `board.chapters[].status` | string | `awaiting` when every scene file of the chapter exists (until the look is approved) or none does yet (a later chapter not started: it has no cards); `authoring` when some of its scene files exist and some do not. Chapter 1's files all exist, so it is never `authoring`. The page shows `being authored` for `authoring` and for a chapter with no card, and `approved` once the database holds an approving answers document of this version, or, on a local page, once the person asks for the approval. |
| `board.plan` | array | The chapter plan, one row per chapter. |
| `board.plan[].chapter` | number | The row's chapter. |
| `board.plan[].title` | string | The chapter's title. |
| `board.plan[].length` | string | The chapter's length, `m:ss`, from the timeline's chapter `start` and `end`; the whole video's for a video with no chapters. |
| `board.plan[].focus` | string | What the chapter teaches, one line: `script.json`'s chapter `focus`, else `storyboard.json`'s `focus`. |
| `board.plan[].sources` | array | The titles of the sources the chapter's scenes cite, in the order first cited, as strings; empty without `excerpts.json`. |
| `board.plan[].status` | string | As `board.chapters[].status`. |
| `board.directions` | array | The three directions, in `storyboard.json`'s order. |
| `board.directions[].id` | string | The direction's id, kebab-case. |
| `board.directions[].name` | string | Its name. |
| `board.directions[].kind` | string | What kind of concept it is (a world, a format, the subject itself). |
| `board.directions[].recommended` | boolean | Whether it is the one recommended. |
| `board.directions[].picked` | boolean | Whether it is the one the scenes are authored in. |
| `board.directions[].frame` | string | Its frame, a still, a path relative to the page. The picked direction's is chapter 1's first scene at its key. |
| `board.kit` | string | The hash of the project's kit files; the guard compares it with the latest answered board's. |
| `board.over` | string or null | The hash of `compositions/over.html`, null without one; the guard compares it with the latest answered board's. |
| `board.assets` | object | Each file under `assets/` but `narration.wav` and `gsap.min.js`, by its path there, to its hash; the guard refuses one of the latest answered board's that changed or went. |
| `board.scenes` | array | Every scene whose composition file exists, in timeline order: all of chapter 1's, and a later chapter's as it is authored. |
| `board.scenes[].id` | string | The scene's id. |
| `board.scenes[].chapter` | number | The chapter it belongs to, `board.chapters[].n`. |
| `board.scenes[].title` | string | Its title, from `storyboard.json`. |
| `board.scenes[].timecode` | string | `m:ss to m:ss`. |
| `board.scenes[].narration` | string | Its sentences from `script.json`, joined by spaces. |
| `board.scenes[].notes` | string | Short staging notes, from `storyboard.json`. |
| `board.scenes[].stills` | object | Its three stills. |
| `board.scenes[].stills.in` | string | The still 0.3 s in, a path relative to the page. |
| `board.scenes[].stills.key` | string | The still at its middle. |
| `board.scenes[].stills.out` | string | The still on its last frame. |
| `board.scenes[].hash` | string | The hash of the scene's composition file; the guard compares it with the latest answered board's. |
| `board.scenes[].changed` | boolean | Whether the hash differs from the latest answered board's, or the last board's before any answers; false on board 1. |

A still is `stills/<first 16 hex of the sha-256 of its bytes>.png`: an
unchanged still keeps its name from one board to the next.

## Answers document

Written by the page to `answers/board-<n>` in the artifact's database, and
accepted by `apply` as JSON in a file:

```json
{ "version": 1, "submittedAt": "2026-10-28T10:00:00.000Z", "approve": false,
  "direction": "kitchen", "look": "warmer", "scenes": [{ "id": "hook", "note": "slower" }] }
```

`version` is the board answered. `approve` is true only for the approval, and
the page offers it only while `direction` is null, `look` is empty and `scenes`
is empty: a comment wins over an approval. `direction` is the id of a direction
other than the one in use, or null. `scenes` holds one entry per scene with a
note, in timeline order.

## Answers text

What the page's copy button and its Submit comment carry, and what `apply`
reads when the answers did not come from the database:

```
creative-video: board <n> answers (database document answers/board-<n>)
Approved: the look
Direction: <id>
Look: <text>
<scene id>: <note>
```

Only the lines that apply. A look or a note of several lines continues on
lines indented two spaces. The comment holds 4096 bytes: a longer text ends
`[cut to fit: read answers/board-<n>]`, which `apply` refuses, and the
document is read from the database instead.

## Who reads what

- The agent writes `storyboard.json` and `directions/<id>.html`; `build` writes
  the board and the page, and `files.json`, the `files` map of the Artifact
  publish: the page's style and script and every still, by the path the page
  names them.
- The page reads the board it embeds. On the artifact page (its db capability
  resolves) it writes the answers document, wakes the session with a comment
  that carries the answers text, and reads the `answers` collection to show a
  chapter approved. Opened as a file, it shows the answers text for the person
  to paste into the terminal.
- `apply` reads the answers document or text and writes `answers-<n>.json`; the
  builds until the next answers read it to guard the scenes and mark what
  changed.
