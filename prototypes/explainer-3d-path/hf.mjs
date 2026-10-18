// PROTOTYPE: one `hyperframes render` through the skill's own tool cache and
// Chrome home, with the composer's flags; prints the wall time in seconds.
// usage: node hf.mjs <composition dir> <out.mp4> [extra hyperframes args]
import path from "node:path";
const lib = path.resolve(
  path.dirname(new URL(import.meta.url).pathname),
  "../../.claude/skills/explainer-video/scripts/lib",
);
const backend = await import(path.join(lib, "backend.mjs"));
const { hyperframesEnv } = await import(path.join(lib, "tools.mjs"));
const [dir, out, ...extra] = process.argv.slice(2);
const t = performance.now();
const code = await backend.hyperframes(
  [
    "render",
    "--strict",
    "--fps",
    "30",
    "--workers",
    "3",
    ...extra,
    "-o",
    path.resolve(out),
  ],
  { cwd: dir, env: hyperframesEnv() },
);
console.log(
  JSON.stringify({
    dir,
    out,
    extra,
    code,
    wall: +((performance.now() - t) / 1000).toFixed(2),
  }),
);
process.exit(code);
