// The pinned HyperFrames CLI, run in a run folder's project, for the agent's
// own checks while it authors scenes (`check`, `snapshot`, `preview`, ...).
//
//   node hf.mjs <run-folder> <hyperframes args...>
//
// Writes the root again (render/root.mjs), so it names the project as it
// stands, then runs the tool cache's HyperFrames in <run>/project with Chrome
// where setup put it, its output on this terminal.
// exit:   the CLI's own code · 1 refused, `hf: <why>` on stderr (no timeline:
//         run render/timing.mjs first) · 2 usage
import fs from "node:fs";
import path from "node:path";
import { stage } from "./lib/stage.mjs";
import { hyperframesEnv, loadBackend } from "./lib/tools.mjs";
import { writeRoot } from "./render/root.mjs";

stage("hf");
const [run, ...args] = process.argv.slice(2);
if (!run || !args.length) {
  console.error("usage: node hf.mjs <run-folder> <hyperframes args>");
  process.exit(2);
}
if (!fs.existsSync(path.join(run, "timeline.json")))
  throw new Error("timeline.json is missing: run render/timing.mjs first");
writeRoot(run);
const cwd = path.join(path.resolve(run), "project");
const backend = await loadBackend();
process.exit(
  await backend.hyperframes(args, {
    cwd,
    env: hyperframesEnv(),
    stdio: "inherit",
  }),
);
