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

const FROM = ["store", "seed", "fetched", "given"];
const KEBAB = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const HEX = /^#[0-9a-f]{6}$/;
const text = (v) => typeof v === "string" && v.trim() !== "";

// A brand held to its shape: throws `<label>: <field> <problem>`.
export function shape(b, label = "brand.json") {
  const bad = (field, problem) => {
    throw new Error(`${label}: ${field} ${problem}`);
  };
  if (!b || typeof b !== "object" || Array.isArray(b))
    throw new Error(`${label}: is not an object`);
  if (!text(b.name) || !KEBAB.test(b.name))
    bad("name", `"${b.name}" is not kebab-case`);
  if (!FROM.includes(b.from)) bad("from", `is not ${FROM.join(", ")}`);
  if (typeof b.once !== "boolean") bad("once", "is not true or false");
  for (const key of ["colours", "faces"])
    if (!Array.isArray(b[key]) || !b[key].length)
      bad(key, "is not a list with at least one entry");
  for (const [i, c] of b.colours.entries()) {
    const at = `colours[${i}]`;
    if (!HEX.test(c?.hex)) bad(`${at}.hex`, "is not a lowercase #rrggbb");
    if (!text(c.name)) bad(`${at}.name`, "is not text");
    if (!["measured", "declared"].includes(c.basis))
      bad(`${at}.basis`, "is not measured or declared");
    if (!text(c.from)) bad(`${at}.from`, "is not text");
  }
  for (const [i, f] of b.faces.entries()) {
    const at = `faces[${i}]`;
    if (!text(f?.family) || !KEBAB.test(f.family))
      bad(`${at}.family`, "is not a Fontsource id");
    if (!text(f.role)) bad(`${at}.role`, "is not text");
    if (!["measured", "declared", "replaced"].includes(f.basis))
      bad(`${at}.basis`, "is not measured, declared or replaced");
    if (f.basis === "replaced")
      for (const key of ["was", "why"])
        if (!text(f[key]))
          bad(
            `${at}.${key}`,
            "is missing: a replaced face names what it replaces (was) and why",
          );
    if (
      f.weights !== undefined &&
      !(Array.isArray(f.weights) && f.weights.every(Number.isFinite))
    )
      bad(`${at}.weights`, "is not a list of numbers");
  }
  if (b.logo !== null && !(text(b.logo?.file) && text(b.logo.source)))
    bad("logo", "is not null or { file, source }");
  if (!Array.isArray(b.fetched)) bad("fetched", "is not a list");
  for (const [i, f] of b.fetched.entries())
    if (!text(f?.url) || !text(f.gave))
      bad(`fetched[${i}]`, "is not { url, gave }");
  if (b.from === "fetched" && !b.fetched.length)
    bad("fetched", "is empty: a fetched brand lists what it fetched");
}

// A brand file parsed: throws `<label>: is not valid JSON (<why>)`.
export function parseBrand(file, label = file) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    throw new Error(`${label}: is not valid JSON (${e.message})`);
  }
}

// The run's brand.json parsed and held to its shape, or null when the run has
// none.
export function readBrand(run) {
  const file = path.join(run, "brand.json");
  if (!fs.existsSync(file)) return null;
  const brand = parseBrand(file, "brand.json");
  shape(brand);
  return brand;
}

// The run's `brand` into the store, whole, unless it was used once: brand.json
// with its logo's name rewritten to the copy beside it, `logo.<ext>`.
export async function saveBrand(run, brand, dirs = userDirs()) {
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
