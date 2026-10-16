# Style extraction

**Style extraction** turns a look the user points at into a draft style
profile. Every source becomes **reference images** first, a script measures
their colours into **colour candidates**, you assign the twelve colour tokens
from those colour candidates by id, and a second script derives what the
images never show and adjusts what fails contrast. You never write a hex:
every colour in the draft is measured, derived or adjusted by a script.

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
   dropped` per colour a page or deck theme declares that no image shows. On
   exit 1, a `style: <row> is not installed` line means run
   `/explainer-video setup` and measure again; a PPTX alone carries no pixels,
   so ask the user to export the deck to PDF and measure again with both files;
   relay any other stderr line.
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
3. **Draft.** `node <skill>/scripts/style/draft.mjs explainers/<slug>
   <name>` prints `style <token>: <hex> · <mark> · <why>` per token, each mark
   `measured`, `derived` or `adjusted` (moved in lightness to pass contrast;
   its `was` and ratios are in the draft's `marks`), then the draft's path,
   `explainers/<slug>/style-draft/<name>.json`. Show the token lines to the
   user. On exit 1, a `style role` line names a role to fix in `roles.json`;
   a `no lightness passes` or `fails contrast` line means the assigned `bg`
   and `text` cannot pass together, so assign one of them another colour
   candidate. Fix `roles.json` and run the draft again. Writing the draft
   deletes the reference images, since a deck may be confidential.

The draft keeps the bundled `claude-code` profile's type, layout, motion, look
and effects, and derives each token you leave out from its colours; the font
names the sources declare are in `candidates.json`'s `fonts`. This
version has no style card or save: tell the user the draft's path, and that
copying it to `explainers/.styles/<name>.json` makes it a project profile a run
can name in `style:`.
