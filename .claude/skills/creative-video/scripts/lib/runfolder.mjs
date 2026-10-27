// The `creative-videos/` folder every run folder sits in. Its `.gitignore`
// keeps a run's recipe (excerpts.json, outline.md, manifest.json, brief.json,
// script.json) committed and everything a stage can rebuild out of git.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { readJson } from "./json.mjs";

const BEGIN = "# creative-video: begin";
const END = "# creative-video: end";
const REBUILDABLE = [
  "voice.json",
  "snapshots/",
  ".cache/",
  "out/",
  "timeline.json",
  "gates.json",
  "project/index.html",
  "project/timing.js",
  "project/compositions/captions.html",
  "project/assets/narration.wav",
  "project/assets/gsap.min.js",
  "project/.hyperframes/",
];
const BLOCK = `${BEGIN} (each run folder commits its recipe only)
${REBUILDABLE.map((f) => `*/${f}`).join("\n")}
${END}
`;

// The `creative-videos/` folder holding `run`: where the `.gitignore` is.
export const creativeVideosDir = (run) => path.dirname(path.resolve(run));

// Writes the skill's block between its markers, leaving every other line of
// the file as the user wrote it.
export function writeIgnore(run) {
  const file = path.join(creativeVideosDir(run), ".gitignore");
  const old = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
  const i = old.indexOf(BEGIN);
  const j = old.indexOf(`${END}\n`, i);
  const next =
    i >= 0 && j > i
      ? old.slice(0, i) + BLOCK + old.slice(j + END.length + 1)
      : old + (old && !old.endsWith("\n") ? "\n" : "") + BLOCK;
  if (next !== old) fs.writeFileSync(file, next);
}

// The hash of the run's voice.json bytes: timeline.json records it, so the
// render knows the timeline still answers to the voice.
export const voiceHash = (run) =>
  crypto
    .createHash("sha256")
    .update(fs.readFileSync(path.join(run, "voice.json")))
    .digest("hex")
    .slice(0, 16);

// timeline.json and voice.json once the run's project is ready to judge or
// render: the timeline exists, answers to this voice.json, and every scene has
// its file. The render and the gates refuse the same three ways; `fail` ends
// the stage with the reason.
export function readTimeline(run, fail) {
  if (!fs.existsSync(path.join(run, "timeline.json")))
    fail("timeline.json is missing: run render/timing.mjs first");
  const timeline = readJson(run, "timeline.json");
  const voice = readJson(run, "voice.json");
  if (timeline.voice !== voiceHash(run))
    fail(
      "timeline.json is from an older voice.json: run render/timing.mjs again",
    );
  const missing = timeline.scenes
    .map((s) => `compositions/${s.id}.html`)
    .filter((f) => !fs.existsSync(path.join(run, "project", f)));
  if (missing.length) fail(`no ${missing.join(", ")}: author each scene file`);
  return { timeline, voice };
}
