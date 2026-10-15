// The `explainers/` folder every run folder sits in. Its `.gitignore` keeps a
// run's recipe (brief.json, script.md, style.json, manifest.json) committed and everything
// a stage can rebuild out of git.
import fs from "node:fs";
import path from "node:path";

const BEGIN = "# explainer-video: begin";
const END = "# explainer-video: end";
const BLOCK = `${BEGIN} (each run folder commits its recipe only)
*/script.json
*/voice.json
*/timeline.json
*/gates.json
*/check.json
*/support.json
*/snapshots/
*/.cache/
*/composition/
*/out/
${END}
`;

// Writes the skill's block between its markers, leaving every other line of
// the file as the user wrote it.
export function writeIgnore(run) {
  const file = path.join(path.dirname(path.resolve(run)), ".gitignore");
  const old = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
  const i = old.indexOf(BEGIN);
  const j = old.indexOf(`${END}\n`, i);
  const next =
    i >= 0 && j > i
      ? old.slice(0, i) + BLOCK + old.slice(j + END.length + 1)
      : old + (old && !old.endsWith("\n") ? "\n" : "") + BLOCK;
  if (next !== old) fs.writeFileSync(file, next);
}
