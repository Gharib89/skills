# Brand

A **brand** is a saved, named look the person can give a video: its colours,
faces and logo. It is optional: run these steps only when the person names a
brand or gives their own material (screenshots, a site, a PDF or PPTX deck, a
video, a logo file). With no brand, the concept owns the whole look.
`<skill>` and `<run>` are as in [SKILL.md](../SKILL.md), and `brand` below is
`node <skill>/scripts/brand/brand.mjs <run>`.

## Contents

- [Get the brand](#get-the-brand)
- [Wear the brand](#wear-the-brand)
- [Approve and save](#approve-and-save)

## Get the brand

1. **Named.** `brand use <name>`, adding `--once` when the person says to use
   it for this video only. It reads the skill's store first, then the seeds
   (`claude-code` and `itworx`: colours and faces, no logo), writes
   `<run>/brand.json`, and runs the check (step 5). On `no brand <name> in the
   store or the seeds`, fetch it (step 2). Material given instead of a name:
   step 2 with that material as the sources, `from` `given`.
2. **Measure.** Find the brand's own brand or press page (its brand
   guidelines, press kit or newsroom), then its site. `brand measure <brand or
   press page> <site> [<file>...]`, the brand page first. Each page is captured
   with the same-site pages its navigation links, each down to 5400 px, and
   colours are measured by area across every page, each page weighing the
   same, so no hero alone decides them. A PPTX gives its theme only: give its
   PDF export beside it. Read the `brand candidate` and `brand font` lines;
   `brand/candidates.json` holds them.
3. **Logo.** Take the first found, in this order: a file the person gave (an
   SVG, or a PNG with transparency); the press page's logo download; an SVG in
   the site's header; the brand's logo file on Wikimedia Commons, its original
   SVG. Never a favicon, a social card (`og:image`) or a trace (a bitmap
   vectorised, or wrapped in an SVG). Save it as `<run>/brand/logo.<ext>`.
   Nothing found: attended, ask the person for a logo file, the only question
   the brand asks; unattended, go on with no logo.
4. **Write `<run>/brand.json`.** `from` `fetched` (or `given`), and every page
   that gave something in `fetched`:

   ```json
   { "name": "acme", "from": "fetched", "once": false,
     "colours": [{ "hex": "#e4002b", "name": "red", "basis": "measured", "from": "https://acme.com/press" }],
     "faces": [{ "family": "inter", "role": "text", "basis": "measured", "weights": [400] },
               { "family": "source-serif-4", "role": "title", "basis": "replaced",
                 "was": "Acme Serif", "why": "not on Fontsource; the nearest admitted serif" }],
     "logo": { "file": "brand/logo.svg", "source": "https://acme.com/press" },
     "fetched": [{ "url": "https://acme.com/press", "gave": "logo, colours" }] }
   ```

   The colours are the brand's anchors, two to five, each `measured` (a
   candidate's hex) or `declared` (named by the brand page but shown by no
   candidate, `from` that page). A face is its Fontsource id: `measured` when
   Fontsource holds the family a `brand font` line names under OFL-1.1 or
   Apache-2.0, else `replaced` by an admitted family of the same class, with
   `was` and a one-line `why`. `logo` is null when none was found.
5. **Check.** `brand check` until it exits 0. It fetches the faces into the
   font store and copies them and the logo into `project/assets/brand/`,
   printing each file's path and each face's Arabic companion (the face an
   Arabic run sets its Arabic in). Act on its last line.

## Wear the brand

The brand fixes the faces, the logo and its colours as the palette's anchors;
the concept gives each colour its meaning in the story and may add one its
world needs (a game show's third state light). `SPEC.md`'s Colour and Type
lines name the brand.

- **All three directions wear it.** Each direction frame and the kit's CSS
  name every brand colour and face: `board build` refuses one that does not.
  The directions still differ in kind of concept.
- **The logo** sits on the opening and closing frames, staged inside the
  concept (on the set, on the product, in the world), never recoloured,
  stretched, cropped or left as a corner watermark. The stills review checks
  it; no gate does.
- **The BANNED list**: the brand's colours and faces pass it, and its banned
  treatments still hold. A banned default the brand needs takes `SPEC.md`'s
  reason line naming the brand.

## Approve and save

Chapter 1's board shows the **brand strip**: each colour measured or
declared, each face measured or replaced, the logo and its source. A look
comment about the brand changes `brand.json`: run `brand check` again, then the
kit and scenes it reaches, and build again. The look approval saves the brand
to the store (`board: brand <name> saved to the store`), so a later video names
it and wears it without asking; one used `--once` is not saved. An unattended
run has no storyboard, so it saves nothing: its `DELIVERY.md` names the brand,
what was fetched and from where, as `credits.mjs` writes them under
`CREDITS.md`'s `## Brand`.

The store is the skill's per-user data folder, `brands/<name>/`; to forget a
brand, delete its folder.
