// The `explainers/` folder every run folder sits in. Its `.gitignore` keeps a
// run's recipe (brief.json, script.md, style.json, manifest.json) committed and everything
// a stage can rebuild out of git.
import fs from "node:fs";
import path from "node:path";

const BEGIN = "# explainer-video: begin";
const END = "# explainer-video: end";
const REBUILDABLE = [
  "script.json",
  "voice.json",
  "timeline.json",
  "gates.json",
  "score.json",
  "check.json",
  "support.json",
  "stills.json",
  "samples.json",
  "board/",
  "storyboard.html",
  "page.css",
  "page-core.js",
  "page-sections.js",
  "page-summary.js",
  "page-boot.js",
  "snapshots/",
  ".cache/",
  "composition/",
  "out/",
  "style-draft/",
];
// A part's run folder, `<run>/parts/<nn>-<title>/`, ignores the same files.
const BLOCK = `${BEGIN} (each run folder commits its recipe only)
${["*/", "*/parts/*/"].flatMap((at) => REBUILDABLE.map((f) => at + f)).join("\n")}
${END}
`;

// A part's run folder is marked by the `part.json` that `parts.mjs start`
// writes. It is a run folder like any other, its brief and excerpts taken from
// the run folder two levels up, which holds the source pack.
export const isPart = (run) => fs.existsSync(path.join(run, "part.json"));

// A part's `part.json`, held to the fields the script gate and delivery read.
// Throws `part.json: <field> ...` for a file of another shape, so a stage
// refuses it by field and neither skips its checks nor dies on a TypeError.
export function readPart(run) {
  let part;
  try {
    part = JSON.parse(fs.readFileSync(path.join(run, "part.json"), "utf8"));
  } catch (e) {
    throw new Error(`part.json is not valid JSON: ${e.message}`);
  }
  const bad = (why) => {
    throw new Error(`part.json: ${why}`);
  };
  const obj = (v) => v && typeof v === "object" && !Array.isArray(v);
  if (!obj(part)) bad("is not an object");
  if (typeof part.series !== "string" || !part.series)
    bad("series is not a name");
  if (!Number.isInteger(part.n) || part.n < 1) bad("n is not a part number");
  if (part.bridge != null) {
    if (!obj(part.bridge) || !Array.isArray(part.bridge.excerpts))
      bad("bridge.excerpts is not a list of ids");
    if (!part.bridge.excerpts.every((x) => typeof x === "string"))
      bad("bridge.excerpts is not a list of ids");
  }
  if (
    part.next != null &&
    (!obj(part.next) || typeof part.next.title !== "string")
  )
    bad("next.title is not a title");
  return part;
}

// The run folder holding `run`'s source pack: itself, or a part's parent.
export const packRun = (run) =>
  isPart(run) ? path.dirname(path.dirname(path.resolve(run))) : run;

// The `explainers/` folder holding `run`: where the style store and the
// `.gitignore` are.
export const explainersDir = (run) => path.dirname(path.resolve(packRun(run)));

// Writes the skill's block between its markers, leaving every other line of
// the file as the user wrote it.
export function writeIgnore(run) {
  const file = path.join(explainersDir(run), ".gitignore");
  const old = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
  const i = old.indexOf(BEGIN);
  const j = old.indexOf(`${END}\n`, i);
  const next =
    i >= 0 && j > i
      ? old.slice(0, i) + BLOCK + old.slice(j + END.length + 1)
      : old + (old && !old.endsWith("\n") ? "\n" : "") + BLOCK;
  if (next !== old) fs.writeFileSync(file, next);
}

// Records uploaded media for a page: each `<path>=<url>` names a file under
// the run folder and the URL its upload returned, which must be https:// or
// the asset store's /_blob/<id>. Returns the URLs by run-relative path,
// `/`-joined as the build commands print it; throws on the first pair it
// cannot record.
export function recordAssets(run, pairs) {
  const root = path.resolve(run);
  const assets = {};
  for (const a of pairs) {
    const i = a.indexOf("=");
    const rel = i < 0 ? "" : a.slice(0, i);
    const url = a.slice(i + 1);
    const abs = path.resolve(root, rel);
    if (
      !rel ||
      !abs.startsWith(root + path.sep) ||
      !fs.existsSync(abs) ||
      !fs.statSync(abs).isFile()
    )
      throw new Error(`${rel || a} is not a file under the run folder`);
    if (!url.startsWith("https://") && !/^\/_blob\/[0-9a-f]{32}$/.test(url))
      throw new Error(`${url} is neither an https:// URL nor /_blob/<id>`);
    assets[path.relative(root, abs).split(path.sep).join("/")] = url;
  }
  return assets;
}
