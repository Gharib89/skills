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
  - `flow`: a chain of 2 to 5 steps joined by arrows (`steps*`, each `at*`,
    `label*`, `note`).
  - `panels`: 2 or 3 side by side (`items*`, each `at*`, `title*`, `body*`).
  - `list`: 1 to 6 points (`title`, `items*`, each `at*`, `text*`).
  - `code`: a highlighted code frame (`lang*`, a Shiki language id; `code*`,
    one string with `\n` between lines, at most 12 lines; `file`;
    `highlights`, each `at*` and `lines*`, `[first, last]` counted from 1).
    The highlights always draw.
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

A profile is schema 2: `colors`, `type` (a face and weight per role), an
optional `scale` and one optional `grammar` block; the loader refuses a schema
1 profile (`motion`, `look`, `effects`) naming what to change. Every grammar
field is optional and a field left out takes today's look, so a profile states
only where it departs:

| Field | Families (default first) | Knobs |
| --- | --- | --- |
| `layout` | `bands` | none |
| `seams` | `cut` | `duration` 0.2 to 0.4 s, `blur` 0 to 24 px |
| `camera` | `locked` | `scale` 1.03 to 1.12 |
| `type` | `block` | `stagger` 0.03 to 0.08 s |
| `ease` | `soft` (every reveal slides up and fades in on one ease), `spring` | none |
| `texture` | `surface`: `flat`, or `sketch`, which outlines flow steps and panels by hand, seeded per scene and element so a render repeats exactly | none |

A field with knobs is a family name or `{ "family": "cut", "duration": 0.3 }`;
a knob out of its range, an unknown family and an unknown field are refused,
naming the field. `bans` lists components the profile refuses: compile stops
on a scene that names one. Flow arrows stroke on and code highlights always
draw.

`scale` overrides the type scale, which the composition exposes as
`--size-<step>` and every component sizes text from: `display` 112, `title`
56, `heading` 46, `body` 40, `code` 32, `small` 28, `label` 24 px. A step
under the 18 px layout floor is refused. The faces are `--font-title`,
`--font-text` and `--font-code` (in an Arabic run the Arabic companions come
first), and the colours are tokens too (see [style.md](style.md)).
