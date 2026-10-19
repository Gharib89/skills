# Scene file

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
  `*`. `at` is a sentence number: that item rises in, or that change plays, as
  the sentence starts.
  - `title` (`kicker`, `title*`, `subtitle`).
  - `cards` (`items*`, each `at*`, `label*`, `value*`, `note`).
  - `terminal` (`title`, `lines*`, each `at*`, `text*`).
  - `flow`: a chain of 2 to 5 steps joined by arrows that stroke on as each
    step arrives (`steps*`, each `at*`, `label*`, `note`).
  - `panels`: 2 or 3 side by side (`items*`, each `at*`, `title*`, `body*`).
  - `list`: 1 to 6 points (`title`, `items*`, each `at*`, `text*`).
  - `code`: a highlighted code frame (`lang*`, a Shiki language id; `code*`,
    one string with `\n` between lines, at most 12 lines; `file`;
    `highlights`, each `at*` and `lines*`, `[first, last]` counted from 1).
  - `codediff`: a code frame that turns `before*` into `after*` at `at*`, the
    removed lines closing and the added ones opening (`lang*`, `file`; each
    side one string like `code`, at most 12 lines).

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
| `layout` | `bands` | none |
| `seams` | `cut` | `duration` 0.2 to 0.4 s, `blur` 0 to 24 px |
| `camera` | `locked` | `scale` 1.03 to 1.12 |
| `type` | `block` | `stagger` 0.03 to 0.08 s |
| `ease` | `soft` (every reveal slides up and fades in on one ease), `spring` (a headline lands with one overshoot; panels, cards, frames and flow nodes settle with a soft one; list items, arrows and terminal lines snap) | none |
| `texture` | `surface`: `flat`, or `sketch`, which outlines flow steps and panels by hand, seeded per scene and element so a render repeats exactly | none |
| `bans` | a list of component names (see Visual above) | none |

A field with knobs is a family name or `{ "family": "cut", "duration": 0.3 }`;
a field without knobs is a family name; `texture` is an object,
`{ "surface": "sketch" }`. A knob out of its range, an unknown family and an
unknown field are refused, naming the field. A scene that names a banned
component stops compile; a ban naming no component is refused.

`scale` overrides steps of the type scale every component sizes text from, as
`{ "body": 44 }`: `display` 112, `title` 56, `heading` 46, `body` 40, `code`
32, `small` 28, `label` 24 px. An unknown step, or any step under the layout
floor (18 px, or the profile's `gates.layout.textPx`), is refused, so a profile
that raises the floor sets each step the new floor passes.
