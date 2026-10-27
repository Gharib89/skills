// The timing stage: everything in the video that comes from timing, generated
// into the HyperFrames project the agent authors its scenes in.
//
//   node timing.mjs <run-folder>
//
// Reads <run>/script.json and <run>/voice.json (held to each other) and times
// every scene back to back on the frame grid (render/grid.mjs) from its voice
// duration, the last held 1 s. Writes <run>/timeline.json (the voice.json's
// hash, the total, each scene's start, duration and absolute word times, the
// caption cues: one per sentence, broken early at a long one) and, in
// <run>/project/, which it creates but otherwise never deletes from or
// touches (the agent's scene files and kit/ live there):
//   assets/narration.wav   the scenes' WAVs joined on the grid
//   assets/gsap.min.js     copied from the tool cache's npm install
//   timing.js              window.TIMING (scene durations and word times local
//                          to each scene) and window.at(scene, word, nth), the
//                          start of the nth matching word, for scene scripts
//   compositions/captions.html   the cues as HyperFrames cue clips
//   index.html             the root: every scene host in order, over.html's
//                          host when the file exists, the captions host, the
//                          narration, and the kit's .css and .js sorted
// stdout: `timing: <n> scene(s), <total> s`, then one `timing: compositions/<id>.html
//         to author` line per scene file not yet written
// exit:   0 timed · 1 refused, `timing: <why>` on stderr · 2 usage
import fs from "node:fs";
import path from "node:path";
import { readJson } from "../lib/json.mjs";
import { HOLD } from "../lib/length.mjs";
import { narrator as findNarrator } from "../lib/narrators.mjs";
import { voiceHash, writeIgnore } from "../lib/runfolder.mjs";
import { stage } from "../lib/stage.mjs";
import { catalogue, dest } from "../lib/tools.mjs";
import { captionCues } from "./cues.mjs";
import { gridScenes, written } from "./grid.mjs";
import { joinNarration, wavSeconds } from "./narration.mjs";

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
const r3 = (n) => +n.toFixed(3);
const RESERVED = ["main", "captions", "over", "narration"];

const script = readJson(run, "script.json");
const voice = readJson(run, "voice.json");
script.scenes.forEach((s, i) => {
  const v = voice.scenes[i];
  if (
    v?.id !== s.id ||
    v.words.map((w) => w.text).join(" ") !== s.narration.join(" ")
  )
    fail(`voice.json does not match scene ${s.id}: run the voice stage again`);
});
if (voice.scenes.length !== script.scenes.length)
  fail("voice.json does not match script.json: run the voice stage again");
const narrator =
  script.narrator ?? findNarrator(undefined, script.language)?.id;
if (voice.narrator !== narrator || voice.language !== script.language)
  fail(
    `voice.json holds narrator ${voice.narrator}, the script asks for ${narrator}: run the voice stage again`,
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
    words: voice.scenes[i].words.map((w) => ({
      text: w.text,
      start: r3(start + w.start),
      end: r3(start + w.end),
    })),
  };
});
const total = written(grid.total);
// A sentence is a list of one-word tokens: a cue breaks at a sentence end, or
// before the word that would take it past the line.
const cues = captionCues(
  script.scenes.map((s) => ({
    captions: s.narration.map((n) =>
      n.split(/\s+/).map((text) => ({ text, words: 1 })),
    ),
  })),
  scenes,
);
fs.writeFileSync(
  path.join(run, "timeline.json"),
  JSON.stringify({ voice: voiceHash(run), total, scenes, cues }, null, 2) +
    "\n",
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

// Word times local to their scene, for scene scripts to cue to.
const local = Object.fromEntries(
  scenes.map((s, i) => [
    s.id,
    {
      duration: s.duration,
      words: voice.scenes[i].words.map((w) => ({
        text: w.text,
        start: r3(w.start),
        end: r3(w.end),
      })),
    },
  ]),
);
fs.writeFileSync(
  path.join(proj, "timing.js"),
  `// Generated by render/timing.mjs: do not edit.
window.TIMING = ${JSON.stringify({ total, scenes: local })};
window.at = (scene, word, nth = 1) => {
  const norm = (s) => s.toLowerCase().replace(/[^\\p{L}\\p{N}]/gu, "");
  const hits = (window.TIMING.scenes[scene]?.words ?? []).filter(
    (w) => norm(w.text) === norm(word),
  );
  if (!hits[nth - 1])
    throw new Error(\`at: no word "\${word}" (\${nth}) in scene \${scene}\`);
  return hits[nth - 1].start;
};
`,
);

const esc = (s) =>
  s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
const cueDivs = cues
  .map(
    (c, i) =>
      `    <div class="cue clip" data-start="${c.start}" data-duration="${(c.end - c.start).toFixed(3)}" id="cue-${i + 1}">${c.tokens
        .map((t) => `<span class="w">${esc(t.text)}</span>`)
        .join(" ")}</div>`,
  )
  .join("\n");
fs.writeFileSync(
  path.join(comps, "captions.html"),
  `<template>
  <style>
    #root {
      position: absolute;
      inset: 0;
    }
    .cue {
      position: absolute;
      left: 160px;
      right: 160px;
      bottom: 96px;
      text-align: center;
      font: 700 44px Inter, sans-serif;
      color: #fff;
      text-shadow: 0 2px 8px rgba(0, 0, 0, 0.85);
    }
  </style>
  <div id="root" data-composition-id="captions" data-width="1920" data-height="1080">
${cueDivs}
  </div>
  <script>
    window.__timelines["captions"] = gsap.timeline({ paused: true });
  </script>
</template>
`,
);

const host = (id, start, duration, track, kind, style = "") =>
  `    <div id="${id}" data-composition-id="${id}" data-composition-src="compositions/${id}.html" data-start="${start}" data-duration="${duration}" data-track-index="${track}" data-track-kind="${kind}" data-width="1920" data-height="1080"${style}></div>`;
const kit = (ext) =>
  fs.existsSync(path.join(proj, "kit"))
    ? fs
        .readdirSync(path.join(proj, "kit"))
        .filter((f) => f.endsWith(ext))
        .sort()
    : [];
fs.writeFileSync(
  path.join(proj, "index.html"),
  `<!doctype html>
<html lang="${script.language}">
  <head>
    <meta charset="utf-8" />
    <title>${esc(path.basename(path.resolve(run)))}</title>
    <style>
      body {
        margin: 0;
      }
    </style>
    <script src="assets/gsap.min.js"></script>
    <script src="timing.js"></script>
${kit(".css")
  .map((f) => `    <link rel="stylesheet" href="kit/${f}" />`)
  .join("\n")}
${kit(".js")
  .map((f) => `    <script src="kit/${f}"></script>`)
  .join("\n")}
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="${total}" data-width="1920" data-height="1080">
${scenes.map((s) => host(s.id, s.start, s.duration, 1, "graphics")).join("\n")}
${fs.existsSync(path.join(comps, "over.html")) ? host("over", 0, total, 2, "graphics") + "\n" : ""}${host("captions", 0, total, 3, "captions", ' style="z-index:10"')}
      <audio id="narration" class="clip" src="assets/narration.wav" data-start="0" data-duration="${total}" data-volume="1" data-track-index="4"></audio>
    </div>
    <script>
      window.__timelines["main"] = gsap.timeline({ paused: true });
    </script>
  </body>
</html>
`.replace(/\n{2,}/g, "\n"),
);

console.log(`timing: ${scenes.length} scene(s), ${total} s`);
for (const s of scenes)
  if (!fs.existsSync(path.join(comps, `${s.id}.html`)))
    console.log(`timing: compositions/${s.id}.html to author`);
