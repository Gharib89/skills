// The brand stage: a video's optional brand, the colours, faces and logo it
// wears (reference/brand.md). The run's brand is <run>/brand.json.
//
//   node brand.mjs <run-folder> use <name> [--once]
//   node brand.mjs <run-folder> measure <source>...
//   node brand.mjs <run-folder> check
//
// use takes the brand <name> from the store, else from the seeds the skill
// ships, into brand.json (`once` for this video only: the board's approval
// then does not save it) and runs check. A store brand's logo is copied to
// <run>/brand/logo.<ext>. measure turns sources into the colour candidates a
// brand written from them must cite (measure.mjs). check holds brand.json to
// what the video can wear and puts the faces and logo in the project
// (check.mjs).
// stdout: each command's, see measure.mjs and check.mjs
// writes: use, <run>/brand.json and brand/logo.<ext>; measure, brand/refs/ and
//         brand/candidates.json; check, brand.json and project/assets/brand/
// exit:   0 ok · 1 refused, `brand: <why>` on stderr (no such brand, a
//         measure or check refusal) · 2 usage
import fs from "node:fs";
import path from "node:path";
import { seedFile, storeDir } from "../lib/brand.mjs";
import { stage } from "../lib/stage.mjs";
import { loadBackend } from "../lib/tools.mjs";
import { check } from "./check.mjs";
import { measure } from "./measure.mjs";

stage("brand");
const [run, command, ...args] = process.argv.slice(2);
const once = args.includes("--once");
const rest = args.filter((a) => a !== "--once");
if (
  !run ||
  !(
    (command === "use" && rest.length === 1) ||
    (command === "measure" && !once && rest.length) ||
    (command === "check" && !args.length)
  )
) {
  console.error(
    "usage: node brand.mjs <run-folder> use <name> [--once] | measure <source>... | check",
  );
  process.exit(2);
}

// The brand `name` from the store, else the seeds, as the run's brand.json.
function use(name) {
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name))
    throw new Error(`name "${name}" is not kebab-case`);
  const stored = path.join(storeDir(name), "brand.json");
  const from = fs.existsSync(stored) ? "store" : "seed";
  const file = from === "store" ? stored : seedFile(name);
  if (!fs.existsSync(file))
    throw new Error(
      `no brand ${name} in the store or the seeds: measure its own pages (brand.mjs <run> measure <url>...) and write brand.json`,
    );
  const {
    from: _,
    once: __,
    ...doc
  } = JSON.parse(fs.readFileSync(file, "utf8"));
  if (doc.logo) {
    const logo = path.join(path.dirname(file), doc.logo.file);
    if (!fs.existsSync(logo)) throw new Error(`${logo}: is missing`);
    const to = `brand/logo${path.extname(logo)}`;
    fs.mkdirSync(path.join(run, "brand"), { recursive: true });
    fs.copyFileSync(logo, path.join(run, to));
    doc.logo = { ...doc.logo, file: to };
  }
  const { name: n, ...tail } = doc;
  fs.mkdirSync(run, { recursive: true });
  fs.writeFileSync(
    path.join(run, "brand.json"),
    JSON.stringify({ name: n, from, once, ...tail }, null, 2) + "\n",
  );
}

if (command === "measure") await measure(run, rest, await loadBackend());
else {
  if (command === "use") use(rest[0]);
  await check(run, await loadBackend());
}
