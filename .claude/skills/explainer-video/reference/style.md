# Style extraction

## Contents

- [Extracting the draft](#extracting-the-draft)
- [The style card](#the-style-card)

**Style extraction** turns a look the user points at into a draft style
profile. Every source becomes **reference images** first, a script measures
their colours into **colour candidates**, you assign the twelve colour tokens
from those colour candidates by id, and a second script derives what the
images never show and adjusts what fails contrast. You never write a hex:
every colour in the draft is measured, derived or adjusted by a script.

## Extracting the draft

Work in a run folder, `explainers/<slug>/`: the video's own run when the
steering prompt points at references, else one named for the profile. Propose
the profile's `<name>` in kebab-case from the source (the site's domain, the
deck's title).

1. **Measure.** `node <skill>/scripts/style/measure.mjs explainers/<slug>
   <source>...`, each source a screenshot (`.png`, `.jpg`, `.jpeg`, `.webp`),
   a web page URL, a `.pdf` or `.pptx` deck, or a video (`.mp4`, `.mov`,
   `.webm`, `.mkv`). It prints `style ref <image>: <kind> · <source>` per
   reference image, `style candidate <id>: <hex> · <share>% · <images>` per
   colour candidate (`s<n>` a surface, ranked by area; `a<n>` an accent, a
   saturated colour), and `style declared <hex>: not in the reference images,
   dropped` per colour a page declares that none of its own images shows, or
   a deck theme declares that its PDF does not show. On exit 1, a
   `style: <row> is not installed` line means run `/explainer-video setup` and
   measure again; a PPTX alone carries no pixels, so ask the user to export the
   deck to PDF and measure again with both files; relay any other stderr line.
2. **Assign.** Look at each image in `explainers/<slug>/style-draft/refs/` with
   the Read tool, then write `explainers/<slug>/style-draft/roles.json`: for
   each token an image shows, the colour candidate playing it and one line on
   where you saw it.

   ```json
   { "bg": { "candidate": "s1", "why": "the ground of every slide" } }
   ```

   | Token | Plays |
   | --- | --- |
   | `bg` | the ground (required) |
   | `panel` | cards and code frames |
   | `chip` | label chips |
   | `line`, `rule` | borders, divider rules |
   | `text` | body text (required) |
   | `muted` | secondary text |
   | `faint` | captions before their word is spoken |
   | `accent` | the brand colour |
   | `ok`, `warn`, `stop` | status colours |

   Leave out a token no image shows: the next step derives it.

   `candidates.json`'s `fonts` lists each family a source declares, with the
   role it plays (`title` or `text`) and its stack's generic family. The first
   family per role plays it when Fontsource holds it under OFL-1.1 or
   Apache-2.0. For a first family Fontsource lacks or does not admit, name the
   nearest admitted Fontsource family under `fonts` in `roles.json`,
   with one line on why it is nearest; add its `class` (`serif`, `sans`,
   `mono` or `display`) when the family carries no `generic`:

   ```json
   { "fonts": { "Helvetica Neue": { "font": "inter", "class": "sans", "why": "a neo-grotesque of the same width" } } }
   ```
3. **Draft.** `node <skill>/scripts/style/draft.mjs explainers/<slug>
   <name>` prints `style <token>: <hex> · <mark> · <why>` per token, each mark
   `measured`, `derived` or `adjusted` (moved in lightness to pass contrast;
   its `was` and ratios are in the draft's `marks`, beside `declared: true`
   on a measured colour a page or theme declared), and `style type <role>:
   <font> · <mark> · <why>` per type role a source decided, each mark
   `measured` (the source's own family), `replaced` (its `was` is the family
   it replaced) or `derived` (an Arabic role's companion of the same class),
   then the draft's path, `explainers/<slug>/style-draft/<name>.json`. A family
   setup does not install is fetched into the font store render reads, and its
   row is carried in the draft's `fonts`. Show the token and type lines to the
   user. On exit 1, a `style role` line names a role to fix in `roles.json`;
   a `style font <family>` line naming `not on Fontsource` or a licence means
   name its replacement under `fonts`, `names no generic family` means add
   the replacement's `class`, one naming the replacement (not on Fontsource,
   its licence, another class) means pick another, and `could not reach
   Fontsource` or `could not fetch it` means run the draft again, relaying
   the line if it repeats;
   a `style <token>: no lightness passes <n>:1 on <surfaces>` or
   `fails contrast` line means no lightness of that token passes on every
   surface it names, which happens when those surfaces sit on opposite sides
   of the lightness scale (a dark `panel` on a light `bg`): assign the
   surface on the other side of the ground another colour candidate, or leave
   it out so the draft derives it, before you touch `text`. Fix `roles.json`
   and run the draft again. Writing the draft
   deletes the reference images, since a deck may be confidential.

The draft keeps the bundled `claude-code` profile's layout, motion (`rise`;
`spring` is the other value a profile may name), look and
effects, and its type for each role no source declares a family for, and
derives each token you leave out from its colours. Show the draft on the style
card next.

A profile's `motion` is `rise` (every reveal slides up and fades in on one
ease) or `spring` (a headline lands with one overshoot, panels, cards, frames
and flow nodes settle with a soft one, list items, arrows and terminal lines
snap). The card shows settled frames, where the two look the same.

## The style card

The **style card** shows the draft on five sample frames (a title, a diagram,
a caption, a code frame, an Arabic frame) over the shared layout, each gated
by the video gates' layout and contrast rules before it shows. The user edits
a colour or a font in place, then saves the profile, uses it once for this
video, or asks for a revision. Its page is
[storyboard/card.html](../storyboard/card.html), and
[storyboard/card-data.md](../storyboard/card-data.md) is the contract between
the page and the script: each **card version** is one document. `card` below
is `node <skill>/scripts/style/card.mjs explainers/<slug> <name>`.

1. **Surface.** As the storyboard's step 2
   ([storyboard.md](storyboard.md)): with `Artifact`, `ArtifactData` or
   `ArtifactComments` missing, or when the user says the page cannot reach its
   database, the card is **local**: skip to step 3 with `card build --local`,
   and tell the user the card is
   `explainers/<slug>/style-draft/card/stylecard.html`, opened in a browser,
   and that they paste its answers text back here.
2. **Publish, once per card.** `card page` writes `style-draft/card/page.html`.
   Publish it as a new artifact: `capabilities` `{"db": {}, "user": {},
   "comments": {}, "assets": {}}`, `icon` `palette`, a one-sentence
   `description`. Refused: the card is local (step 1). Never publish it again:
   every later change is a card version. Record its URL with `card page
   <url>`. Arm the watch as the storyboard's step 3 says.
3. **Build.** `card build`, adding `--local` on a local card, and `--project`
   when the user asked for a project profile, so the card names the store Save
   writes (by default the user store when this copy of the skill sits under
   `~/.claude/skills` or `~/.agents/skills`, else the project's
   `explainers/.styles/`). Exit 1 with `card: ... is not installed` means run
   `/explainer-video setup`; `fails contrast` or `names font` names what to fix
   in the draft; relay any other `card:` line. On a published page it first
   lists `card: upload <path> (<size>)` per font file the page does not hold:
   upload them as the storyboard's step 4 uploads, record each with `card
   asset <path>=<url> ...`, and build again. On exit 0 it prints `card <n>: 5
   frame(s), <k> finding(s) -> style-draft/card/<n>.json` and a `card <gate>
   <frame>: <what>` line per finding; a finding blocks Save and Use once on the
   page, so say which frame broke which rule. Published: write that file with
   `ArtifactData` `set`, collection `cards`, doc id `<n>`, `file_path` the
   file. Then print the page link or the local path and `Style card <n>
   posted.`, and end the turn.
4. **Read a Submit.** As the storyboard's step 5: published, `ArtifactData`
   `get` collection `answers`, doc id `card-<n>`, with `out_dir`
   `explainers/<slug>/style-draft/card/inbox`; with no such document, or
   local, write the comment's or the pasted text to
   `explainers/<slug>/style-draft/card/inbox/answers.txt`. Run step 5 on the
   file, and resolve the Submit thread once the next version is posted or the
   profile is saved or used.
5. **Apply.** `card apply <file>`, adding `--project` as step 3 did. It
   prints:
   - `card: rebuild`: the edits are in the draft, whatever the choice; build
     the next version (step 3).
   - `card: revise: <note>`: change `roles.json` as the note asks, run the
     draft again (it needs no reference images), then build the next
     version. A note that needs a hex no candidate holds is a colour edit on
     the card: build the next version unchanged and ask the user to make the
     edit there.
   - `card: saved <name> -> <file>[, default of the <scope> store]`: tell the
     user the profile is saved there, and that `style: <name>` names it.
   - `card: once <name> -> style.json`: the profile is this run's alone. Run
     `brief.mjs explainers/<slug> style=<name>` and go on with the video.

   `answers for card <a>, the latest is card <b>`: read the latest version's
   answers instead; with none, ask the user to Submit card `<b>`. Any other
   `card:` refusal (a name the store took since the card was built, a
   project profile of the name hiding a user save, a finding): relay it as
   printed and build the next version (step 3), which the page answers afresh.
