// Shared fixtures of the chapter tests: a run folder whose scenes are voiced by
// tones of whole frames (maintainer/real-render-lib.mjs), so a scene's length is
// set to the frame, and whose script.json carries a chapter plan.
import fs from "node:fs";
import path from "node:path";
import { runFolder } from "../../skills/creative-video/maintainer/real-render-lib.mjs";
import { fixture } from "./voice-lib.mjs";
import { install } from "./timing-lib.mjs";

// Frames of a chapter's scenes: 3240 frames are 108 s, the 2 minute floor.
export const MIN = 3240;

// `scenes` is `[{ id, frames, html? }]`; `chapters` the plan's `scenes` lists
// (and titles) to write into script.json, `brief` brief.json's content. The run
// folder is `demo` on a temp machine with the npm row installed, not yet timed.
export function chaptered(scenes, { chapters, brief } = {}) {
  const fx = fixture();
  install(fx);
  const dir = runFolder(path.dirname(fx.dir), "demo", scenes);
  const out = { ...fx, dir };
  setPlan(out, chapters);
  if (brief)
    fs.writeFileSync(path.join(dir, "brief.json"), JSON.stringify(brief));
  return out;
}

// script.json rewritten with `chapters` (or none).
export function setPlan(fx, chapters) {
  const file = path.join(fx.dir, "script.json");
  const script = JSON.parse(fs.readFileSync(file, "utf8"));
  if (chapters) script.chapters = chapters;
  else delete script.chapters;
  fs.writeFileSync(file, JSON.stringify(script));
}

// A chapter of the plan: its title, focus and scene ids.
export const chapter = (title, ...scenes) => ({
  title,
  focus: `what ${title} teaches`,
  scenes,
});
