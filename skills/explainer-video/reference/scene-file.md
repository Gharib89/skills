# Scene file

## Contents

- [The scene file](#the-scene-file)
- [Style profiles](#style-profiles)

## The scene file

The shape of `explainers/<slug>/script.md`, the render stage's input:

````markdown
# How Ship lands a pull request
language: en
narrator: am_fenrir

## Scene hook · The promise

### Narration
1. Ship opens {42|forty two} pull requests, each one `merged`. [ex-3]
2. Here is how. [no-claim]

### Visual
```json
{ "component": "title", "props": { "kicker": "Ship", "title": "Issue to pull request" } }
```
````

- **Header.** Only `language`, `narrator` and `style`. `language` defaults to
  `en`; `narrator` and `style` are optional.
  With a brief in the run folder, compile takes all three from it and refuses
  a header key that names another value.
- **Scenes.** `## Scene <id> · <title>`, the id kebab-case and not `main`,
  then optionally `role: <role> · <n> s` (see Script), which the script gates
  need.
- **Narration.** Numbered sentences in spoken form; an indented line continues
  the sentence above, so its cites go on the last line. `{written|spoken}`
  shows the written form in the captions and voices the spoken one; backticks
  are dropped. A caption breaks only between written tokens, so each holds at
  most 84 characters. Every sentence ends in `[a, b]`, its cites, or in
  `[no-claim]` when it makes no claim.
- **Visual.** One JSON block per scene, one component, required props marked
  `*`. A prop a component does not take is refused at compile, in an item as
  much as at the top. An optional `seam` beside `component` (`zoom-through`,
  `cut-the-curve` or `cut`) sets the seam out of this scene; with none the
  composer picks from the arc: a zoom-through where the next scene's role
  differs (or either has none), a cut on a curve inside a beat. Compile
  refuses a `seam` outside the profile's seams family and `cut`. An optional
  `camera` beside `component`, `{ "at*", "on" }`, is the scene's **camera
  beat**, the cue its push-in lands on; with none, the camera beat is the cue
  of the last item to reveal. A cue under one push duration into the scene
  runs the push from the scene's start. Compile refuses a `camera` key under a
  profile that bans `camera` or whose camera family is `locked`, and on a rich
  component, which draws its own camera. A
  **cue** is `at`, a sentence number: that item rises in, or that change
  plays, as the sentence starts. Add `on`, a phrase of that sentence in its
  spoken form, and it lands on the phrase's first spoken word instead;
  compile refuses a phrase the sentence does not say (case and punctuation
  aside), and a phrase said twice takes its first place. `on` goes wherever
  `at` does, on an item and on `codediff` too.
  - `title` (`kicker`, `title*`, `subtitle`).
  - `cards` (`items*`, each `at*`, `label*`, `value*`, `note`).
  - `terminal` (`title`, `lines*`, each `at*`, `text*`).
  - `flow`: a chain of 2 to 5 steps joined by arrows that stroke on as each
    step arrives (`steps*`, each `at*`, `label*`, `note`).
  - `panels`: 2 or 3 side by side (`items*`, each `at*`, `title*`, `body*`).
  - `list`: 1 to 6 points (`title`, `items*`, each `at*`, `text*`).
  - `code`: a syntax-coloured code frame (`lang*`, a Shiki language id;
    `code*`, one string with `\n` between lines, at most 12 lines; `file`).
    `highlights`, which earlier versions took, is refused: name the lines in
    `emphasis`.
  - `codediff`: a code frame that turns `before*` into `after*` at `at*`, the
    removed lines closing and the added ones opening (`lang*`, `file`; each
    side one string like `code`, at most 12 lines).
  - `emphasis`, a prop of `cards`, `terminal`, `flow`, `panels`, `list` and
    `code` (`title` and `codediff` take none): one callout per scene,
    `{ "target*", "at*", "on" }`, drawn as a ring round the target with a
    leader line, revealed on its cue. `target` is the text of one item (its
    `label`; a panel's `title`; a `text` for a terminal line or list item),
    matched exactly, and refused when it matches no item or more than one, or
    when its cue falls before the item's own, the callout sitting inside it. On
    `code` it is a line range, `[first, last]` counted from 1.

## Style profiles

Style profiles are looked up in three stores, first match winning: the
project's `explainers/.styles/`, the user config store's `styles/`, and the
skill's bundled `<skill>/styles/`. The header's `style:` names one; without it,
the first store holding a `default` file (one profile name) decides, else
`claude-code`. A run copies its profile to `<run>/style.json` and keeps using
that copy, so a later edit to a store never changes this video; delete the
copy to take up the edit, or name another profile in `style:`.

A profile holds `"schema": 2` (a profile without it is read as schema 1),
`colors` (the tokens in [style.md](style.md)), `type` (a face and weight per
role), and optionally `fonts` (families the draft fetched), `gates` (floors it
may only tighten), `scale` and one `grammar` block. The loader refuses a
schema 1 profile (`motion`, `look`, `effects`, `layout`), naming each
change. Every grammar field is optional; a field left out takes its default,
the family listed first, so a profile states only where it departs:

| Field (under `grammar`) | Families (default first) | Knobs |
| --- | --- | --- |
| `layout` | `open` (no header band, content from the top down to the captions), `bands` (a header band above the content) | none |
| `seams` | `velocity` (the outgoing scene draws the seam and runs on past its last moment while the next starts on time: a zoom-through at a beat change, a cut on a curve inside a beat), `cut` (a hard cut) | `duration` 0.2 to 0.4 s (default 0.2, whole frames), `blur` 0 to 24 px (default 18, the zoom-through's peak; the cut on a curve peaks at 4/9 of it) |
| `camera` | `push` (one push-in per scene, landing on its camera beat and held to the scene's end), `locked` (no push-in) | `scale` 1.03 to 1.12 (default 1.06, the push-in's end scale), `duration` 0.4 to 1.6 s (default 0.8) |
| `type` | `block` | `stagger` 0.03 to 0.08 s |
| `ease` | `velocity` (every reveal slides up and fades in on a fast-out ease: `power3` for most, `power4` for a headline, `expo` for list items, arrows and terminal lines), `soft` (every reveal on one `power2` ease), `spring` (a headline lands with one overshoot; panels, cards, frames and flow nodes settle with a soft one; list items, arrows and terminal lines snap) | none |
| `texture` | `surface`: `glass` (boxes half see-through, blurred behind, over the colour field), `flat`, or `sketch`, which outlines flow steps and panels by hand, seeded per scene and element so a render repeats exactly; `overlays`: a list of `field` (a blurred field in the profile's colours behind the scenes), `grain` (noise at a fixed seed), `vignette` and `depth` (everything but the emphasised item blurs once the emphasis lands), all four by default | `grain` opacity 0 to 0.3, `fieldBlur` 0 to 240 px, `depthBlur` 0 to 24 px |
| `bans` | a list of component names (see Visual above) and techniques: `draw`, which strokes the arrows of `flow` on, so banning it refuses every `flow` scene; `blur`, which the texture sets as `fieldBlur` and `depthBlur`, so banning it refuses a profile whose `field` or `depth` overlay has a blur above 0, whose surface is `glass`, whose boxes blur what is behind them (set `flat` or `sketch`), or whose `velocity` seams have a `blur` above 0 (set it to 0 or use the `cut` family); `camera`, the push-in, so banning it draws none and refuses a scene's `camera` key | none |

A field with knobs is a family name or `{ "family": "cut", "duration": 0.3 }`;
a field without knobs is a family name; `texture` is an object,
`{ "surface": "flat", "overlays": ["vignette"] }`. A profile with no grammar
block plays the first family of every field: the open layout, glass over a
colour field with grain, a vignette and depth blur, and the velocity eases. A
knob out of its range, an unknown family and an unknown field are refused,
naming the field. A scene that names a banned
component, or one that uses a banned technique, stops compile; a ban naming
neither is refused.

`scale` overrides steps of the type scale every component sizes text from, as
`{ "body": 44 }`: `display` 112, `title` 56, `heading` 46, `body` 40, `code`
32, `small` 28, `label` 24 px. An unknown step, or any step under the layout
floor (18 px, or the profile's `gates.layout.textPx`), is refused, so a profile
that raises the floor sets each step the new floor passes.
