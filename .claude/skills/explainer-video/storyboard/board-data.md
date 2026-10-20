# Board data

The one contract between a run and [page.html](page.html), the storyboard
page. `scripts/storyboard/board.mjs build` writes one **board document** per
board version; the page writes one **answers document** per Submit. On the
artifact page both live in the page's database, written and read with
`ArtifactData`. Every `build` also writes the board into the run folder's
`storyboard.html`; without a database the human opens that file and pastes
its answers text back.

## Contents

- [Documents](#documents)
- [Fields](#fields)
- [Card status](#card-status)
- [Recommendation](#recommendation)
- [Menus](#menus)
- [Answers text](#answers-text)
- [Media](#media)

## Documents

| Document | Written by | When |
|---|---|---|
| collection `boards`, doc id `<n>` (`1`, `2`, ...) | the run, `ArtifactData` `set` with `board/<n>.json`'s contents | once per board version |
| collection `answers`, doc id `board-<n>` | the page, on Submit | once per Submit of version `<n>` |

A board version is never rewritten once the human can see it, and the page is
never republished: a revision, a gate stop and the delivery are each a new
version.

## Fields

`board.` is a board document, `answers.` an answers document; `[]` is an array
element. Required reads `yes` in every version, `delivered` only in a version
of that kind, `no` never. The page reads and writes nothing outside this table.

| Path | Type | Required | Meaning |
|---|---|---|---|
| `board.version` | number | yes | The version's number, the same as its doc id. |
| `board.kind` | `"review"` or `"delivered"` | yes | Cards to approve or revise, or the finished video's clips. |
| `board.title` | string | yes | The scene file's title. |
| `board.build` | string | yes | The live build every card and the animatic play: the video's composition as one `.js` asset, a [media](#media) URL. |
| `board.narration` | string | yes | The whole narration joined, as audio-only WebM, a media URL. The animatic plays it. |
| `board.brief` | array | yes | The brief, one entry per knob and list, in `brief.json` order. |
| `board.brief[].knob` | string | yes | `focus`, `length`, `audience`, `language`, `style`, `voice`, `aspect`, `score`, `must` or `avoid`. |
| `board.brief[].value` | string | yes | The value; a list's items joined by `; `. |
| `board.brief[].type` | `"menu"`, `"number"` or `"text"` | yes | How the page offers the knob: a menu of `options`, a number (`length`, in minutes), or free text. |
| `board.brief[].options` | array | no | A menu knob's options, as strings: `language`, `style`, `voice`, `aspect` and `score`. |
| `board.voices` | array | yes | The narrators each language offers, one entry per language. The `voice` menu shows the entry of the language the human has picked. |
| `board.voices[].language` | string | yes | The language code. |
| `board.voices[].options` | array | yes | That language's narrator ids, as strings. |
| `board.sources` | array | yes | The source pack, one entry per source. Empty for narration the user wrote. |
| `board.sources[].id` | string | yes | The source's id. |
| `board.sources[].kind` | string | yes | `repo`, `page`, `pdf`, ... |
| `board.sources[].title` | string | yes | The source's title. |
| `board.sources[].summary` | string | yes | Its reader's summary. |
| `board.sources[].excerpts` | number | yes | How many excerpts the pack holds from it. |
| `board.kept` | array | no | An Arabic run's kept terms, in order of first use in the scenes, then any the title alone uses: the English words it says, shows and captions as written. Shown editable with the brief. |
| `board.banner` | object | no | Present on the version a gate stop posted. |
| `board.banner.text` | string | yes | Why the run stopped, then a sentence asking to revise the reopened cards when any reopened. |
| `board.banner.gates` | array | yes | Each red gate's line as `gates.mjs` printed it. |
| `board.scenes` | array | yes | One card per scene, in order. |
| `board.scenes[].id` | string | yes | The scene id. |
| `board.scenes[].title` | string | yes | The scene's title. |
| `board.scenes[].role` | string | no | Its role (`hook`, `context`, `point`, `recap`, `end`). |
| `board.scenes[].seconds` | number | yes | Its voiced length in seconds. |
| `board.scenes[].start` | number | yes | Where the scene begins in the joined narration and the build, in seconds. |
| `board.scenes[].slot` | number | yes | The scene's voiced length plus its exit seam, in seconds: the stretch its card loops. |
| `board.scenes[].narration` | string | yes | The scene file's narration lines for the scene, exactly as written, numbers, `{written\|spoken}` and cites included. |
| `board.scenes[].style` | string | yes | Style notes: the visual's component (followed by `past the default` for a rich one), the profile and the narrator. |
| `board.scenes[].rich` | boolean | yes | Whether its visual is a rich component, one that moves the frame itself. The overview counts these. |
| `board.scenes[].recommendation` | `"approve"` or `"revise"` | yes | The agent's recommendation, which the card opens on. See [Recommendation](#recommendation). |
| `board.scenes[].finding` | string | no | The reds on the card, one per line: what the sampling pass left, then a gate stop's evidence naming the scene. |
| `board.scenes[].fix` | string | no | The agent's proposed fix for the finding. Only a card with a finding has one. |
| `board.scenes[].still` | string | yes | The scene's still at its fullest moment, a [media](#media) URL. |
| `board.scenes[].audio` | string | yes | The scene's narration as audio-only WebM, a media URL. |
| `board.scenes[].clip` | string | delivered | The delivered video's stretch for this scene, an MP4 media URL. |
| `board.scenes[].status` | `"open"`, `"approved"` or `"reopened"` | yes | See [Card status](#card-status). |
| `board.scenes[].menus` | object | yes | The card's four [menus](#menus), each set to the agent's pick. |
| `board.scenes[].menus.component` | object | yes | The scene's component menu. |
| `board.scenes[].menus.component.pick` | string | yes | The component now in the scene. |
| `board.scenes[].menus.component.options` | array | yes | Every component the profile does not ban, then `custom`. |
| `board.scenes[].menus.component.disabled` | boolean | no | True when the menu cannot change on this card. |
| `board.scenes[].menus.camera` | object | yes | The scene's camera beat menu. |
| `board.scenes[].menus.camera.pick` | string | yes | The beat now in the scene, as a cue value. |
| `board.scenes[].menus.camera.options` | array | yes | The scene's cues as cue values, in order of place. |
| `board.scenes[].menus.camera.disabled` | boolean | no | True on a rich or custom card, or when the profile bans or locks the camera. |
| `board.scenes[].menus.emphasis` | object | yes | The scene's emphasised item menu. |
| `board.scenes[].menus.emphasis.pick` | string | yes | The item now emphasised, or `none`. |
| `board.scenes[].menus.emphasis.options` | array | yes | `none`, then each item label the scene names once. |
| `board.scenes[].menus.emphasis.disabled` | boolean | no | True when the component has no item to emphasise. |
| `board.scenes[].menus.seam` | object | yes | The menu for the seam out of the scene. |
| `board.scenes[].menus.seam.pick` | string | yes | The seam move now planned, or `cut`. |
| `board.scenes[].menus.seam.options` | array | yes | The moves of the profile's seam family, then `cut`. |
| `board.scenes[].menus.seam.disabled` | boolean | no | True on the last scene, which has no seam out. |
| `answers.version` | number | yes | The version answered. |
| `answers.submittedAt` | string | yes | ISO 8601 time of the Submit. |
| `answers.scenes` | array | yes | One entry per card, in order. |
| `answers.scenes[].id` | string | yes | The scene id. |
| `answers.scenes[].choice` | `"approve"` or `"revise"` | yes | The human's answer. |
| `answers.scenes[].note` | string | yes | What to change; empty when none. |
| `answers.scenes[].narration` | string | yes | The edited narration lines; empty when unedited. |
| `answers.scenes[].picks` | object | yes | The card's changed menu picks, by menu; empty when none changed. See [Menus](#menus). |
| `answers.scenes[].picks.component` | string | no | The component picked. |
| `answers.scenes[].picks.camera` | string | no | The camera beat picked, as a cue value. |
| `answers.scenes[].picks.emphasis` | string | no | The item picked, or `none`. |
| `answers.scenes[].picks.seam` | string | no | The seam move picked, or `cut`. |
| `answers.brief` | array | yes | `<knob>=<value>` arguments for `brief.mjs`, one per changed knob and one per list item of a changed list; empty when none changed. |
| `answers.kept` | array | no | Present when the board has `kept`: one entry per kept term respelt; empty when none changed. |
| `answers.kept[].term` | string | yes | The kept term as the board listed it. |
| `answers.kept[].to` | string | yes | Its new spelling, never empty. |

Text fields are plain text; the page interprets nothing in them.

## Card status

- `open`: new or changed since the last version the human answered. Arrives on
  its `recommendation`.
- `approved`: approved on the last version and unchanged since. Shown
  collapsed; it can still be revised.
- `reopened`: named by a red gate's evidence on the version a gate stop
  posted. Arrives on `revise` when its finding is the red gate's evidence.

## Recommendation

Every card of a review version opens on its `recommendation`: `revise` when it
has a `finding` and its status is not `approved`, else `approve`. The page
opens on an overview of every `still` with counts read off this document: the
cards with `rich` set, the cards with a `finding` and the cards whose status is
not `approved`. **Approve all and submit** answers every card `approve`, a
card with a finding included, and submits. A note or an edited narration on a
card answers it `revise`. A card's answer is the human's choice, whatever the
recommendation was.

A `delivered` version holds every card `approved`, and its page takes no
answers. `build` makes one only while the delivered MP4 is at least as new as
`stills.json`: new stills mean a changed script, so the next version is a
review.

## Menus

The page hardcodes no option: every menu on a card and in the brief lists what
the board document gives it, and opens on the pick the agent made. A menu with
`disabled` set shows its pick and takes no change. A card's menu set to
another option turns the card to `revise` and joins `answers.scenes[].picks`,
which holds changed picks only. On a locked page every menu is disabled.

- **Cue value.** A camera beat is `<at>` (a sentence number) or `<at> <phrase>`
  (the sentence, then a phrase of it); the menu lists the scene's own cues.
- **Written picks.** `board.mjs apply` writes a camera, emphasis or seam pick
  into the scene's visual in `script.md`, so the run rebuilds only the scenes
  whose picks, narration or note changed; every other scene stays cached.
- **Component pick.** Each component's props differ, so `apply` writes none:
  it prints `board <id> pick: component=<x>` and the scene joins the redo set,
  which the agent rebuilds as that component.
- **Brief knobs.** A `menu` knob is a select of its `options`; `voice` takes
  the options of the language the human picked from `board.voices`, and
  changing the language resets the voice to the first of the new language's.
  A `number` knob is a number of minutes; a `text` knob is free text.

## Answers text

The Submit comment carries the answers as text, and the page's copy fallback
(and the local `storyboard.html`) shows the same text: `board.mjs apply` reads
either it or the answers document. One line per form, in this order:

| Line | When |
|---|---|
| `explainer-video: board <n> answers (database document answers/board-<n>)` | always, first |
| `<id>: Approve` or `<id>: Revise` | each card |
| `  note: <text>` | under a card with a note; a note's own line breaks become spaces |
| `  narration:` | under a card whose narration was edited |
| `    <line>` | each edited narration line, under `  narration:`, four spaces then the line as written |
| `  pick: <menu>=<value>` | under a card, one per changed menu pick, after its note and narration |
| `Brief: <knob>=<value>` | each `answers.brief` entry |
| `Kept: <term> -> <to>` | each `answers.kept` entry |
| `[cut to fit: read answers/board-<n>]` | last, when the text was cut to a comment's 4 KiB |

## Media

`build`, `narration`, `still`, `audio` and `clip` are URLs the page uses as
given. On the artifact page each is the URL the asset upload returned,
recorded with `board.mjs asset`. In `storyboard.html`, and in every version
built before a page is recorded or with `build --local`, each is the file's
path relative to the run folder. `build` refuses a media file over 15 MB, the
asset cap. The page drops a URL that is not `https:`, `/_blob/` or a relative
path.

The build is a script, not a picture: the page loads it with `<script src>` and
plays it in a frame with `sandbox="allow-scripts"` and nothing else, which
works the same from a published page and from `file:`. A card shows its
`still` until it is in view, then plays the build over `start` for `slot`
seconds in a loop.
