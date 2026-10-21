# Card data

The one contract between a run and [card.html](card.html), the style card
page. `scripts/style/card.mjs build` writes one **card document** per card
version; the page writes one **answers document** per Submit. On the artifact
page both live in the page's database, written and read with `ArtifactData`.
Every `build` also writes the card into `style-draft/card/stylecard.html`;
without a database the human opens that file and pastes its answers text back.

## Contents

- [Documents](#documents)
- [Fields](#fields)
- [Submit](#submit)
- [Answers text](#answers-text)
- [Media](#media)

## Documents

| Document | Written by | When |
|---|---|---|
| collection `cards`, doc id `<n>` (`1`, `2`, ...) | the run, `ArtifactData` `set` with `style-draft/card/<n>.json`'s contents | once per card version |
| collection `answers`, doc id `card-<n>` | the page, on Submit | once per Submit of version `<n>` |

A card version is never rewritten once the human can see it, and the page is
never republished: an edit or a revision is a new version.

## Fields

`card.` is a card document, `answers.` an answers document; `[]` is an array
element. Required reads `yes` or `no`. A `map` is an object keyed by colour
token or type role. The page reads and writes nothing outside this table.

| Path | Type | Required | Meaning |
|---|---|---|---|
| `card.version` | number | yes | The version's number, the same as its doc id. |
| `card.name` | string | yes | The draft's name, kebab-case: the name it saves under unless the human renames it. |
| `card.label` | string | yes | The draft's display name, the page's heading. |
| `card.source` | string | yes | Where the draft came from; empty when unknown. |
| `card.colors` | array | yes | One entry per colour token, in the draft's order. |
| `card.colors[].token` | string | yes | The token: `bg`, `panel`, `chip`, `line`, `rule`, `text`, `muted`, `faint`, `accent`, `ok`, `warn` or `stop`. |
| `card.colors[].hex` | string | yes | Its `#rrggbb` value. |
| `card.colors[].mark` | string | yes | How the value was reached: `measured`, `derived`, `adjusted`, `edited`, or `bundled` for a profile with no marks. |
| `card.colors[].why` | string | yes | The mark's reason; empty when none. |
| `card.roles` | array | yes | Contrast by role, one entry per role, as `lib/style.mjs` holds it. |
| `card.roles[].min` | number | yes | The role's floor, the profile's own when it tightens the skill's. |
| `card.roles[].tokens` | array | yes | The text tokens of the role. |
| `card.roles[].on` | array | yes | The surface tokens they sit on. |
| `card.type` | array | yes | One entry per type role: `title`, `text`, `code`, `arTitle`, `arText`. |
| `card.type[].role` | string | yes | The role. |
| `card.type[].font` | string | yes | The font family the draft names. |
| `card.type[].mark` | string | no | How the family was reached: `measured` (the source's own), `replaced` (the nearest admitted family for one the source names), `derived` (an Arabic role's companion) or `edited`; absent for a bundled role. |
| `card.type[].why` | string | no | The mark's reason, present with `mark`. |
| `card.families` | array | yes | The font families setup installs and those the draft fetched, the choices for `title`, `text` and `code`. |
| `card.fonts` | array | yes | The font files the frames load. |
| `card.fonts[].file` | string | yes | The file name a frame's `url("fonts/<file>")` names. |
| `card.fonts[].url` | string | yes | Where the page loads it from, a [media](#media) URL. |
| `card.live` | object | yes | The live build the frames play. |
| `card.live.url` | string | yes | Where the page loads `live.js` from, a [media](#media) URL. |
| `card.grammar` | array | yes | One entry per grammar field, in the order `scripts/style/grammar.mjs` lists them. |
| `card.grammar[].field` | string | yes | The field's path under `grammar`, such as `seams.blur`. |
| `card.grammar[].value` | string | yes | The value the draft plays, as text; a list joined by commas, `none` for an empty one. |
| `card.grammar[].mark` | string | yes | How the field was reached: `measured`, `judged`, `bundled` (the profile states it with no mark) or `default` (the draft leaves it out). |
| `card.grammar[].why` | string | yes | The mark's reason; empty for `default` and for a mark with none. |
| `card.frames` | array | yes | The sample frames, in order: title, diagram, caption, code, Arabic, then a seam. |
| `card.frames[].id` | string | yes | The frame id. |
| `card.frames[].label` | string | yes | Its heading on the page. |
| `card.frames[].html` | string | yes | The frame as a whole 1920x1080 page with no script, the draft's palette as `--<token>` properties on `:root`. It stays the frame's poster until the live build mounts. |
| `card.frames[].loop` | array | yes | `[from, to]` in seconds: the stretch of the live build the frame loops, a sample's own scene through its exit seam, and for the seam frame the title-to-diagram seam with half a second either side. |
| `card.findings` | array | yes | Each layout or contrast finding as `<gate> <frame>: <what>`; empty when every frame passed. |
| `card.scope` | `"user"` or `"project"` | yes | The store Save writes to. |
| `card.taken` | array | yes | The profile names that store holds already. |
| `answers.version` | number | yes | The version answered. |
| `answers.submittedAt` | string | yes | ISO 8601 time of the Submit. |
| `answers.choice` | `"save"`, `"once"` or `"revise"` | yes | Save to the store, use for this video only, or revise the draft. |
| `answers.name` | string | yes | The name to save or use it under, kebab-case. |
| `answers.colors` | map | yes | Each edited token's new `#rrggbb`, lowercase; empty when none. |
| `answers.type` | map | yes | Each edited role's new family; empty when none. |
| `answers.note` | string | yes | What to change; empty when none. |
| `answers.replace` | boolean | yes | Save over the profile of the same name in the store. |
| `answers.default` | boolean | yes | Make the saved profile the store's default. |

Text fields are plain text; the page interprets nothing in them, and puts a
frame's `html` only in a sandboxed frame that runs no script.

## Submit

Submit stays off until a choice is picked, the name is kebab-case, every
colour passes contrast by role with the edits applied, Replace is ticked when
Save names a profile the store holds, and, when the card has findings, the
choice is Revise or a colour or font is edited. What `card.mjs apply` then
writes and prints is in step 5 of
[reference/style.md](../reference/style.md#the-style-card).

## Answers text

The Submit comment carries the answers as text, and the page's copy fallback
(and the local `stylecard.html`) shows the same text: `card.mjs apply` reads
either it or the answers document. One line per form, in this order:

| Line | When |
|---|---|
| `explainer-video: style card <n> answers (database document answers/card-<n>)` | always, first |
| `Choice: Save`, `Choice: Use once` or `Choice: Revise` | always |
| `Name: <name>` | always |
| `Colour <token>: <hex>` | each edited colour |
| `Font <role>: <family>` | each edited font |
| `Replace: yes` | when `replace` |
| `Default: yes` | when `default` |
| `Note: <text>` | when a note was written; its line breaks become spaces |

## Media

`fonts[].url` is a URL the page puts in a frame's `@font-face` as given. On
the artifact page each is the URL the asset upload returned, recorded with
`card.mjs asset`. In `stylecard.html`, and in every version built with `build
--local` or before a page is recorded, each is `frames/fonts/<file>`, relative
to the card folder. The page drops a URL that is not `https:`, `/_blob/` or a
relative path, or that holds a quote, a bracket, a backslash or a space.
`live.url` is the live build the same way: the uploaded URL on the artifact
page, recorded with `card.mjs asset style-draft/card/live.js=<url>`, and
`live.js` beside the page otherwise. A build that changes `live.js` drops its
recorded upload, so upload it again.
