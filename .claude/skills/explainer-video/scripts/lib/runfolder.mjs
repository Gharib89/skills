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

// The `explainers/` folder holding `run`: where the style store and the
// `.gitignore` are.
export function explainersDir(run) {
  const up = (dir, n) => (n ? up(path.dirname(dir), n - 1) : dir);
  return up(path.resolve(run), isPart(run) ? 3 : 1);
}

// The run folder holding `run`'s source pack: itself, or a part's parent.
export const packRun = (run) =>
  isPart(run) ? path.dirname(path.dirname(path.resolve(run))) : run;

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
