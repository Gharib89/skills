// The run's brand (`<run>/brand.json`) and where a brand lives between runs:
// the store beside the font store (`<data>/brands/<name>/`, written when a
// board is approved) and the seeds the skill ships (`brands/<name>.json`, no
// logo: a mark is a trademark and the repo is public). Shared by the brand
// stage, the board and the credits.
import fs from "node:fs";
import path from "node:path";
import { skill, staged } from "./tools.mjs";
import { userDirs } from "./paths.mjs";

export const storeDir = (name, dirs = userDirs()) =>
  path.join(dirs.data, "brands", name);
export const seedFile = (name) => path.join(skill, "brands", `${name}.json`);

// The run's brand.json parsed, or null when the run has none.
export function readBrand(run) {
  const file = path.join(run, "brand.json");
  if (!fs.existsSync(file)) return null;
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    throw new Error(`brand.json: is not valid JSON (${e.message})`);
  }
}

// The Arabic face that goes with a Latin family, by the family's Fontsource
// category: a serif beside a naskh, a sans or a mono beside Plex, a display or
// handwriting face beside a kufi.
export const COMPANION = {
  serif: "noto-naskh-arabic",
  "sans-serif": "ibm-plex-sans-arabic",
  monospace: "ibm-plex-sans-arabic",
  display: "noto-kufi-arabic",
  handwriting: "noto-kufi-arabic",
};

// The run's brand into the store, whole, unless it was used once: brand.json
// with its logo's name rewritten to the copy beside it, `logo.<ext>`.
export async function saveBrand(run, dirs = userDirs()) {
  const brand = readBrand(run);
  if (brand.once) return { name: brand.name, saved: false };
  await staged(storeDir(brand.name, dirs), async (part) => {
    const doc = structuredClone(brand);
    if (doc.logo) {
      const to = `logo${path.extname(doc.logo.file)}`;
      fs.copyFileSync(path.join(run, doc.logo.file), path.join(part, to));
      doc.logo.file = to;
    }
    fs.writeFileSync(
      path.join(part, "brand.json"),
      JSON.stringify(doc, null, 2) + "\n",
    );
  });
  return { name: brand.name, saved: true };
}

// A binary PPM's size and its RGB bytes.
export function decodePpm(buf) {
  const m = buf
    .subarray(0, 64)
    .toString("latin1")
    .match(/^P6\s+(\d+)\s+(\d+)\s+255\s/);
  if (!m) throw new Error("not a binary PPM");
  return { w: +m[1], h: +m[2], px: buf.subarray(m[0].length) };
}

// OKLab (Björn Ottosson's), where a declared colour is compared with a
// measured one: `[L, a, b]` from a #rrggbb.
export function oklab(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  const [l, m, s] = [
    0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
    0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
    0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
  ].map(Math.cbrt);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}
