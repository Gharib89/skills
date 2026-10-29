// What the storyboard stage does with the run's brand (board.mjs): holds the
// frames to it, puts it in the board document and holds an approval to what
// the board showed. `fail` ends the stage with the reason.
import fs from "node:fs";
import path from "node:path";
import { readBrand } from "../lib/brand.mjs";

// A face is named where its id, or the id spaced, stands as a whole word: no
// letter, digit or hyphen either side, so `cursor:pointer` names no inter.
const names = (text, family) =>
  [family, family.replaceAll("-", " ")].some((n) =>
    new RegExp(`(?<![a-z0-9-])${n}(?![a-z0-9-])`).test(text),
  );

// Each direction frame not picked and the kit's CSS must wear the brand: name
// every one of its colours and faces, so the three directions and the scenes
// are all in the brand, not only the picked one.
export function wearBrand(run, brand, directions, fail) {
  const kit = path.join(run, "project", "kit");
  const css = (fs.existsSync(kit) ? fs.readdirSync(kit).sort() : [])
    .filter((f) => f.endsWith(".css"))
    .map((f) => fs.readFileSync(path.join(kit, f), "utf8"))
    .join("\n");
  const wearers = [
    ...directions.list
      .filter((d) => d.id !== directions.picked)
      .map((d) => [
        `directions/${d.id}.html`,
        fs.readFileSync(path.join(run, "directions", `${d.id}.html`), "utf8"),
      ]),
    ["project/kit/*.css", css],
  ];
  for (const [file, body] of wearers) {
    const text = body.toLowerCase();
    for (const { hex } of brand.colours)
      if (!text.includes(hex.toLowerCase()))
        fail(`${file} does not wear the brand: it names no ${hex}`);
    for (const { family } of brand.faces)
      if (!names(text, family))
        fail(`${file} does not wear the brand: it names no ${family}`);
  }
}

// The board document's `brand`, null without one: the logo named by the hash
// of its bytes, as a still is. It writes nothing, so an approval can hold the
// brand to what the board showed.
export function brandStrip(run, brand, sha, fail) {
  if (!brand) return null;
  let logo = null;
  if (brand.logo) {
    const from = path.join(run, brand.logo.file);
    if (!fs.existsSync(from))
      fail(`brand.json: logo ${brand.logo.file} is missing`);
    logo = {
      file: `brand/${sha(fs.readFileSync(from))}${path.extname(from).toLowerCase()}`,
      source: brand.logo.source,
    };
  }
  return {
    name: brand.name,
    from: brand.from,
    once: brand.once,
    colours: brand.colours.map(({ hex, name, basis, from }) => ({
      hex,
      name,
      basis,
      from,
    })),
    faces: brand.faces.map(({ family, role, basis, was }) => ({
      family,
      role,
      basis,
      was: was ?? null,
    })),
    logo,
  };
}

// The strip's logo copied into the board folder: the files it adds.
export function copyLogo(run, out, brand, strip) {
  if (!strip?.logo) return [];
  fs.mkdirSync(path.join(out, "brand"), { recursive: true });
  fs.copyFileSync(
    path.join(run, brand.logo.file),
    path.join(out, strip.logo.file),
  );
  return [strip.logo.file];
}

// The run's brand an approval of board `n` saves (null without one), refused
// unless its strip is `shown`, the one board `n` showed.
export function approvedBrand(run, shown, n, sha, fail) {
  const brand = readBrand(run);
  if (
    JSON.stringify(brandStrip(run, brand, sha, fail)) !==
    JSON.stringify(shown ?? null)
  )
    fail(
      `brand.json changed since board ${n} showed it: build the board again`,
    );
  return brand;
}
