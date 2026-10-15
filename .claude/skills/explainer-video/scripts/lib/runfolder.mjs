// The `explainers/` folder every run folder sits in. Its `.gitignore` keeps a
// run's recipe (script.md, style.json, manifest.json) committed and everything
// a stage can rebuild out of git.
import fs from "node:fs";
import path from "node:path";

const IGNORE = `# Written by explainer-video: each run folder commits its recipe only.
*/script.json
*/voice.json
*/timeline.json
*/gates.json
*/snapshots/
*/.cache/
*/composition/
*/out/
`;

export function writeIgnore(run) {
  const file = path.join(path.dirname(path.resolve(run)), ".gitignore");
  if (!fs.existsSync(file) || fs.readFileSync(file, "utf8") !== IGNORE)
    fs.writeFileSync(file, IGNORE);
}
