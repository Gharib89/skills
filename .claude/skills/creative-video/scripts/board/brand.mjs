// What the storyboard stage does with the run's brand (board.mjs): holds the
// frames to it and puts it in the board document. `fail` ends the stage with
// the reason.
import fs from "node:fs";
import path from "node:path";

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
      if (!text.includes(family) && !text.includes(family.replaceAll("-", " ")))
        fail(`${file} does not wear the brand: it names no ${family}`);
  }
}

// The board document's `brand` (null without one) and the files it adds to
// the board folder: the logo, copied under the hash of its bytes like a still.
export function boardBrand(run, out, brand, sha, fail) {
  if (!brand) return { doc: null, files: [] };
  const files = [];
  let logo = null;
  if (brand.logo) {
    const from = path.join(run, brand.logo.file);
    if (!fs.existsSync(from))
      fail(`brand.json: logo ${brand.logo.file} is missing`);
    const name = `brand/${sha(fs.readFileSync(from))}${path.extname(from).toLowerCase()}`;
    fs.mkdirSync(path.join(out, "brand"), { recursive: true });
    fs.copyFileSync(from, path.join(out, name));
    files.push(name);
    logo = { file: name, source: brand.logo.source };
  }
  return {
    doc: {
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
    },
    files,
  };
}
