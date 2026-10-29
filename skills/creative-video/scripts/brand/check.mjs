// The brand stage's `check`: the run's brand.json held to its shape and to what
// the video can wear, then its faces and logo put in the project
// (`brand.mjs <run> check`; `use` runs it too).
//
// Shape: name kebab-case; from store, seed, fetched or given; colours and faces
// not empty; a colour's basis measured or declared; a face's basis measured,
// declared or replaced (replaced names `was` and `why`); logo null or `{file,
// source}`; fetched not empty when the brand was fetched. A `measured` colour
// of a fetched or given brand must be a candidate of brand/candidates.json.
// Each face must be on Fontsource under OFL-1.1 or Apache-2.0; its weights snap
// to the ones the family has and the font store gets them. A logo is an .svg or
// a .png with transparency, never a favicon or a social card, and an SVG
// embeds no raster image.
// stdout: `brand: <name> (<from>[, once])`, a `brand colour <hex> <name>:
//         <basis> · <from>` line per colour, a `brand face <role> <family>
//         <weights>: <basis>[, was <was>] · <licence> · arabic <companion> ·
//         <woff2 files>` line per face, `brand logo: <file> · <source>` or
//         `brand logo: none`, and for a fetched or given brand with no logo
//         `brand: no logo found: ask the person for one (unattended: say so in
//         DELIVERY.md)`
// writes: brand.json with each face's licence, version, companion and weights
//         filled, the font store's files, <run>/project/assets/brand/ (each
//         face's weights as <family>-<weight>.woff2, and logo.<ext>)
// refuses: each as one line after the stage's `brand: `. A refusal of the
//         shape, a colour, a face's family or licence, or the logo writes
//         nothing; a face that fails to install leaves the faces before it in
//         the font store and project/assets/brand/, and brand.json as it was
import fs from "node:fs";
import path from "node:path";
import { readBrand } from "../lib/brand.mjs";
import { dest, installFont, LICENCES } from "../lib/tools.mjs";

const NOT_LOGO =
  /favicon|apple-touch-icon|og[-_]?image|twitter[-_]?(card|image)|social[-_]?card/i;

// The Arabic face that goes with a Latin family, by the family's Fontsource
// category: a serif beside a naskh, a sans or a mono beside Plex, a display or
// handwriting face beside a kufi.
const COMPANION = {
  serif: "noto-naskh-arabic",
  "sans-serif": "ibm-plex-sans-arabic",
  monospace: "ibm-plex-sans-arabic",
  display: "noto-kufi-arabic",
  handwriting: "noto-kufi-arabic",
};

// A PNG holds transparency when its colour type has an alpha channel (4, 6) or
// it carries a tRNS chunk.
function transparent(png) {
  if (png.subarray(1, 4).toString() !== "PNG") return false;
  const colourType = png[25];
  if (colourType === 4 || colourType === 6) return true;
  for (let o = 8; o + 8 <= png.length; o += 12 + png.readUInt32BE(o))
    if (png.subarray(o + 4, o + 8).toString() === "tRNS") return true;
  return false;
}

// Throws when the logo is not the mark; returns its extension.
function logoOf(run, logo) {
  const refuse = (why) => {
    throw new Error(`logo ${logo.file}: ${why}`);
  };
  const file = path.join(run, logo.file);
  if (!fs.existsSync(file)) refuse("is missing");
  const ext = path.extname(file).toLowerCase();
  if (
    ext === ".ico" ||
    NOT_LOGO.test(path.basename(file)) ||
    NOT_LOGO.test(logo.source)
  )
    refuse("a favicon or social card is never the logo");
  if (![".svg", ".png"].includes(ext)) refuse("is not an .svg or a .png");
  const bytes = fs.readFileSync(file);
  if (ext === ".png" && !transparent(bytes))
    refuse("has no transparency: a box behind the mark is not the mark");
  if (ext === ".svg") {
    const svg = bytes.toString("utf8");
    if (!/<svg/i.test(svg)) refuse("holds no <svg>");
    if (/<image/i.test(svg))
      refuse(
        "embeds a raster image: a trace or a wrapped bitmap, not the mark",
      );
  }
  return ext;
}

// Each asked weight snapped to the nearest the family has, no repeat, sorted.
const snap = (asked, has) =>
  [
    ...new Set(
      asked.map(
        (w) =>
          [...has].sort(
            (a, b) => Math.abs(a - w) - Math.abs(b - w) || a - b,
          )[0],
      ),
    ),
  ].sort((a, b) => a - b);

export async function check(run, backend) {
  const brand = readBrand(run);
  if (!brand) throw new Error("brand.json: is missing");

  if (["fetched", "given"].includes(brand.from)) {
    const file = path.join(run, "brand", "candidates.json");
    const c = fs.existsSync(file)
      ? JSON.parse(fs.readFileSync(file, "utf8"))
      : {};
    const seen = new Set(
      [...(c.surfaces ?? []), ...(c.accents ?? [])].map((x) => x.hex),
    );
    for (const col of brand.colours)
      if (col.basis === "measured" && !seen.has(col.hex))
        throw new Error(
          `colour ${col.hex} is marked measured but brand/candidates.json has no such candidate`,
        );
  }

  const metas = [];
  for (const f of brand.faces) {
    const meta = await backend.fontMeta(f.family);
    if (!meta)
      throw new Error(
        `face ${f.family}: Fontsource has no such family: name an admitted replacement (basis replaced, with was and why)`,
      );
    if (!LICENCES.includes(meta.license))
      throw new Error(
        `face ${f.family}: licence ${meta.license}, only ${LICENCES.join(" or ")}: name an admitted replacement (basis replaced, with was and why)`,
      );
    metas.push(meta);
  }
  const logoExt = brand.logo && logoOf(run, brand.logo);

  const assets = path.join(run, "project", "assets", "brand");
  fs.mkdirSync(assets, { recursive: true });
  for (const [i, f] of brand.faces.entries()) {
    const meta = metas[i];
    f.weights = snap(f.weights ?? [400, 700], meta.weights);
    f.licence = meta.license;
    f.version = meta.npmVersion;
    f.companion = COMPANION[meta.category];
    const row = {
      id: `font:${f.family}`,
      kind: "font",
      family: f.family,
      version: f.version,
    };
    // The store's folder is rewritten whole, so the files it already holds
    // stay in the list: two runs never shrink it.
    const folder = dest(row);
    const held = fs.existsSync(folder)
      ? fs
          .readdirSync(folder)
          .filter((n) => n.endsWith(".woff2"))
          .map((n) => path.basename(n, ".woff2"))
      : [];
    row.files = [
      ...new Set([...f.weights.map((w) => `latin-${w}-normal`), ...held]),
    ];
    const got = await installFont(row, backend);
    if (got !== "present") throw new Error(`face ${f.family}: ${got}`);
    for (const w of f.weights)
      fs.copyFileSync(
        path.join(folder, `latin-${w}-normal.woff2`),
        path.join(assets, `${f.family}-${w}.woff2`),
      );
  }
  if (brand.logo)
    fs.copyFileSync(
      path.join(run, brand.logo.file),
      path.join(assets, `logo${logoExt}`),
    );
  fs.writeFileSync(
    path.join(run, "brand.json"),
    JSON.stringify(brand, null, 2) + "\n",
  );

  console.log(
    `brand: ${brand.name} (${brand.from}${brand.once ? ", once" : ""})`,
  );
  for (const c of brand.colours)
    console.log(`brand colour ${c.hex} ${c.name}: ${c.basis} · ${c.from}`);
  for (const f of brand.faces)
    console.log(
      `brand face ${f.role} ${f.family} ${f.weights.join(",")}: ${f.basis}${f.was ? `, was ${f.was}` : ""} · ${f.licence} · arabic ${f.companion} · ${f.weights.map((w) => `assets/brand/${f.family}-${w}.woff2`).join(", ")}`,
    );
  console.log(
    brand.logo
      ? `brand logo: assets/brand/logo${logoExt} · ${brand.logo.source}`
      : "brand logo: none",
  );
  if (!brand.logo && ["fetched", "given"].includes(brand.from))
    console.log(
      "brand: no logo found: ask the person for one (unattended: say so in DELIVERY.md)",
    );
}
