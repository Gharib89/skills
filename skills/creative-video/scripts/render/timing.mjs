// The timing stage: everything in the video that comes from timing, generated
// into the HyperFrames project the agent authors its scenes in.
//
//   node timing.mjs <run-folder>
//
// Reads <run>/script.json and <run>/voice.json (held to each other) and times
// every scene back to back on the frame grid (render/grid.mjs) from its voice
// duration, the last held 1 s. Writes <run>/timeline.json (the voice.json's
// hash, the total, each scene's start, duration and absolute word times, the
// caption cues: one per sentence, broken early at a long one, a cue naming
// its role when the video has two or more and the last cue's differs, and, when
// script.json carries `chapters`, each chapter's number, title, window and scenes
// on the grid) and, in <run>/project/, which it creates but otherwise never deletes from or
// touches (the agent's scene files and kit/ live there):
//   assets/narration.wav   the scenes' WAVs joined on the grid
//   assets/gsap.min.js     copied from the tool cache's npm install
//   assets/ibm-plex-sans-arabic-600.woff2   an Arabic run's caption face,
//                          copied from the font store
//   timing.js              window.TIMING (scene starts in the video, durations
//                          and word times local to each scene) and
//                          window.at(scene, word, nth), the
//                          start of the nth matching word, for scene scripts
//   compositions/captions.html   the cues as HyperFrames cue clips
//   index.html             the root (render/root.mjs)
// stdout: `timing: <n> scene(s), <total> s`, then one `timing: compositions/<id>.html
//         to author` line per scene file not yet written
// exit:   0 timed · 1 refused, `timing: <why>` on stderr (an Arabic run whose
//         caption face is not installed, a plan of chapters
//         that does not fit the scenes, a chapter under 2 or over 6 minutes
//         within 10%, a brief over 6 minutes with no plan) · 2 usage
import fs from "node:fs";
import path from "node:path";
import { maybeJson, readJson } from "../lib/json.mjs";
import { rolesOf, voices, voicesOf } from "../lib/kit.mjs";
import { HOLD } from "../lib/length.mjs";
import { voiceHash, writeIgnore } from "../lib/runfolder.mjs";
import { stage } from "../lib/stage.mjs";
import { catalogue, dest, fontGap } from "../lib/tools.mjs";
import { planChapters } from "./chapters.mjs";
import { captionCues } from "./cues.mjs";
import { gridScenes, written } from "./grid.mjs";
import { joinNarration, wavSeconds } from "./narration.mjs";
import {
  CAPTION_FACE,
  captionsHtml,
  shift,
  timingJs,
  timingScenes,
} from "./project.mjs";
import { writeRoot } from "./root.mjs";

stage("timing");
const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node timing.mjs <run-folder>");
  process.exit(2);
}
function fail(why) {
  console.error(`timing: ${why}`);
  process.exit(1);
}
const RESERVED = ["main", "captions", "over", "narration"];

const script = readJson(run, "script.json");
const voice = readJson(run, "voice.json");
script.scenes.forEach((s, i) => {
  const v = voice.scenes[i];
  if (
    v?.id !== s.id ||
    v.words.map((w) => w.text).join(" ") !== s.narration.join(" ") ||
    JSON.stringify(v.roles) !== JSON.stringify(rolesOf(s))
  )
    fail(`voice.json does not match scene ${s.id}: run the voice stage again`);
});
if (voice.scenes.length !== script.scenes.length)
  fail("voice.json does not match script.json: run the voice stage again");
// Each role's voice and style as script.json and the cast ask for them now; a
// narrator speaks one language, so the voices hold the script's language too.
const asked = voicesOf(voices(run, script));
const held = voice.voices;
const said = (n) =>
  n ? `${n.narrator}${n.style ? ` ("${n.style}")` : ""}` : "no voice";
for (const role of new Set([...Object.keys(asked), ...Object.keys(held)]))
  if (said(asked[role]) !== said(held[role]))
    fail(
      `voice.json holds ${role} ${said(held[role])}, the script asks for ${said(asked[role])}: run the voice stage again`,
    );
// A scene id is a file name, an element id and a timeline key.
for (const { id } of script.scenes) {
  if (!/^[a-z0-9-]+$/.test(id))
    fail(`scene id ${id} is not lower-case letters, digits and hyphens`);
  if (RESERVED.includes(id))
    fail(`scene id ${id} is reserved (${RESERVED.join(", ")})`);
}
const npm = catalogue().find((r) => r.kind === "npm");
if (!fs.existsSync(path.join(dest(npm), ".stamp")))
  fail(`${npm.id} is not installed: run /creative-video setup`);
const face =
  script.language === "ar" &&
  catalogue().find((r) => r.id === "font:ibm-plex-sans-arabic");
const faceGap = face && fontGap(face);
if (faceGap) fail(`${faceGap}: run /creative-video setup`);

// Scenes back to back on the frame grid, every word time absolute.
const grid = gridScenes(
  voice.scenes.map((v) => wavSeconds(run, v.audio, fail)),
  HOLD,
);
const scenes = script.scenes.map((s, i) => {
  const start = written(grid[i].start);
  return {
    id: s.id,
    start,
    duration: written(grid[i].frames),
    words: shift(voice.scenes[i].words, start),
  };
});
const total = written(grid.total);
// A sentence is a list of one-word tokens: a cue breaks at a sentence end, or
// before the word that would take it past the line.
const cues = captionCues(
  script.scenes.map((s, i) => ({
    captions: s.narration.map((n) =>
      n.split(/\s+/).map((text) => ({ text, words: 1 })),
    ),
    roles: voice.scenes[i].roles,
  })),
  scenes,
);
// A video over 6 minutes is written in chapters; a plan is held to the scenes.
const brief = maybeJson(run, "brief.json");
if (brief?.length > 6 && !script.chapters)
  fail(
    `brief.json asks for ${brief.length} minutes, over 6: plan the video in chapters (script.json chapters)`,
  );
const chapters =
  script.chapters &&
  planChapters(
    script.chapters,
    script.scenes.map((s) => s.id),
    grid,
    fail,
  );
fs.writeFileSync(
  path.join(run, "timeline.json"),
  JSON.stringify(
    { voice: voiceHash(run), total, scenes, cues, chapters },
    null,
    2,
  ) + "\n",
);
writeIgnore(run);

const proj = path.join(run, "project");
const comps = path.join(proj, "compositions");
fs.mkdirSync(comps, { recursive: true });
fs.mkdirSync(path.join(proj, "assets"), { recursive: true });
joinNarration({
  run,
  voice,
  frames: grid.map((g) => g.frames),
  file: path.join(proj, "assets", "narration.wav"),
  fail,
});
fs.copyFileSync(
  path.join(dest(npm), "node_modules", "gsap", "dist", "gsap.min.js"),
  path.join(proj, "assets", "gsap.min.js"),
);

// Word times local to their scene, for scene scripts to cue to, and the scene's
// start in the video, which a sound a script creates is placed by.
const local = timingScenes(scenes, voice, (s) => s.start);
fs.writeFileSync(path.join(proj, "timing.js"), timingJs(total, local));
if (face)
  fs.copyFileSync(
    path.join(dest(face), "arabic-600-normal.woff2"),
    path.join(proj, CAPTION_FACE),
  );
fs.writeFileSync(
  path.join(comps, "captions.html"),
  captionsHtml(cues, script.language),
);

writeRoot(run);

console.log(`timing: ${scenes.length} scene(s), ${total} s`);
for (const s of scenes)
  if (!fs.existsSync(path.join(comps, `${s.id}.html`)))
    console.log(`timing: compositions/${s.id}.html to author`);
