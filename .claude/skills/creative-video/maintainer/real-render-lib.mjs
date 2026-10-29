// Maintainer only: the run folders real-render.mjs and calibrate-render-rates.mjs
// render, the stages they run, and the frame comparison real-render.mjs reads
// the renders with.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { voicesOf } from "../scripts/lib/kit.mjs";
import { narrator } from "../scripts/lib/narrators.mjs";
import { catalogue, dest, skill } from "../scripts/lib/tools.mjs";
import { FPS } from "../scripts/render/grid.mjs";
import { HEIGHT, WIDTH } from "../scripts/render/root.mjs";

const RATE = 24000;

// A mono 16-bit WAV of `hz` exactly `n` frames long: at 220 Hz the narration
// stand-in.
export function tone(n, hz = 220) {
  const pcm = Buffer.alloc(((n * RATE) / FPS) * 2);
  for (let i = 0; i < pcm.length / 2; i++)
    pcm.writeInt16LE(
      Math.round(3000 * Math.sin((2 * Math.PI * hz * i) / RATE)),
      i * 2,
    );
  const h = Buffer.alloc(44);
  h.write("RIFF", 0, "ascii");
  h.writeUInt32LE(36 + pcm.length, 4);
  h.write("WAVEfmt ", 8, "ascii");
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20);
  h.writeUInt16LE(1, 22);
  h.writeUInt32LE(RATE, 24);
  h.writeUInt32LE(RATE * 2, 28);
  h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34);
  h.write("data", 36, "ascii");
  h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}

// A freely authored scene: a box sliding and turning across the scene's whole
// length, so every frame differs from the one before.
const composition = (id, hue) => `<template>
  <style>
    #root {
      position: absolute;
      inset: 0;
      background: hsl(${hue}, 40%, 18%);
    }
    .box {
      position: absolute;
      top: 380px;
      left: 160px;
      width: 240px;
      height: 240px;
      background: hsl(${hue}, 70%, 70%);
    }
  </style>
  <div id="root" data-composition-id="${id}" data-width="${WIDTH}" data-height="${HEIGHT}">
    <div class="box" id="${id}-box"></div>
  </div>
  <script>
    window.__timelines["${id}"] = gsap
      .timeline({ paused: true })
      .to("#${id}-box", { x: 1280, rotation: 180, ease: "none", duration: window.TIMING.scenes["${id}"].duration }, 0);
  </script>
</template>
`;

// A scene file the way the agent writes one: `body` its markup on a dark
// ground, `js` the script that adds to its timeline `tl`.
export const authored = (id, body, js = "") => `<template>
  <style>
    #root {
      position: absolute;
      inset: 0;
      background: #20242c;
    }
  </style>
  <div id="root" data-composition-id="${id}" data-width="${WIDTH}" data-height="${HEIGHT}">
    ${body}
  </div>
  <script>
    const tl = gsap.timeline({ paused: true });
    ${js}
    window.__timelines["${id}"] = tl;
  </script>
</template>
`;

// The run folder `<dir>/<name>` in `language` as the voice stage and the agent
// leave it, voiced by the language's default narrator: one
// scene per `{ id, frames, html }`, voiced by a tone exactly `frames` long with
// its two words spread over it, and its composition authored (the sliding box,
// or `html`). Each sentence states no fact, so it cites nothing and the support
// checker's verdict is `connective`. The claims check passes it, the timing
// stage times it, the render stage renders it.
export function runFolder(dir, name, scenes, language = "en") {
  const run = path.join(dir, name);
  const comps = path.join(run, "project", "compositions");
  fs.mkdirSync(path.join(run, "voice"), { recursive: true });
  fs.mkdirSync(comps, { recursive: true });
  const narration = (id) => `Scene ${id}.`;
  fs.writeFileSync(
    path.join(run, "script.json"),
    JSON.stringify({
      language,
      scenes: scenes.map(({ id }) => ({
        id,
        narration: [narration(id)],
        cites: [[]],
      })),
    }),
  );
  fs.writeFileSync(
    path.join(run, "excerpts.json"),
    JSON.stringify({ excerpts: [] }),
  );
  fs.writeFileSync(
    path.join(run, "support.json"),
    JSON.stringify({
      sentences: scenes.map(({ id }) => ({
        scene: id,
        n: 1,
        text: narration(id),
        cites: [],
        verdict: "connective",
        why: "It names the scene and states no fact.",
      })),
    }),
  );
  const voiced = scenes.map(({ id, frames, html }, i) => {
    const audio = `voice/${id}.wav`;
    fs.writeFileSync(path.join(run, audio), tone(frames));
    fs.writeFileSync(
      path.join(comps, `${id}.html`),
      html ?? composition(id, (i * 137) % 360),
    );
    const half = frames / FPS / 2;
    const [first, second] = narration(id).split(" ");
    return {
      id,
      audio,
      duration: frames / FPS,
      words: [
        { text: first, start: 0, end: half },
        { text: second, start: half, end: 2 * half },
      ],
      qc: { failures: [] },
      roles: ["narrator"],
    };
  });
  const n = narrator(undefined, language);
  fs.writeFileSync(
    path.join(run, "voice.json"),
    JSON.stringify({
      narrator: n.id,
      language,
      voices: voicesOf({ narrator: n }),
      scenes: voiced,
    }),
  );
  return run;
}

// The frames at which two hash lists differ, each frame past the shorter
// list's end included.
export const differing = (a, b) =>
  Array.from({ length: Math.max(a.length, b.length) }, (_, i) => i).filter(
    (i) => a[i] !== b[i],
  );

// The rows a real render needs that are not installed: the npm-packages and
// chrome rows, and ffmpeg and ffprobe on PATH.
export function missingRows() {
  const missing = catalogue()
    .filter((r) => ["npm", "chrome"].includes(r.kind))
    .filter((r) => !fs.existsSync(path.join(dest(r), ".stamp")))
    .map((r) => r.id);
  if (["ffmpeg", "ffprobe"].some((t) => spawnSync(t, ["-version"]).error))
    missing.push("ffmpeg");
  return missing;
}

// The stdout of `cmd`; a failure throws with both streams, since the render
// stage prints its delivery failures on stdout and its renderer on stderr.
export function capture(cmd, args) {
  const r = spawnSync(cmd, args, { encoding: "utf8", maxBuffer: 1 << 26 });
  if (r.status !== 0) {
    const files = args.filter(path.isAbsolute).map((a) => path.basename(a));
    const said = [r.stdout, r.stderr].map((s) => s?.trim()).filter(Boolean);
    throw new Error(
      `${path.basename(cmd)} ${files.join(" ")}: ${said.join("\n") || r.error?.message}`,
    );
  }
  return r.stdout;
}

// Runs the skill's stage `script` (under scripts/) on `run` with `more`
// arguments after it; the MP4 it would deliver.
export function runStage(script, run, ...more) {
  capture(process.execPath, [
    path.join(skill, "scripts", script),
    run,
    ...more,
  ]);
  return path.join(run, "out", `${path.basename(run)}.mp4`);
}

// The claims check and the gates passed on `run`. The critic gate waits on a
// verdict per scene: a clean one is written for each pending scene, as
// agents/critic.md writes one, since the critic's judgement is a live probe's
// to prove, not these scripts'.
export function gatesPass(run) {
  runStage("source/claims.mjs", run);
  const gates = path.join(skill, "scripts", "gates", "gates.mjs");
  spawnSync(process.execPath, [gates, run], { maxBuffer: 1 << 26 });
  const record = path.join(run, "gates.json");
  const critic =
    fs.existsSync(record) &&
    JSON.parse(fs.readFileSync(record, "utf8")).gates.critic;
  if (critic?.status === "pending") {
    const dir = path.join(run, critic.stills);
    const set = JSON.parse(fs.readFileSync(path.join(dir, "stills.json")));
    for (const [id, stills] of Object.entries(set))
      fs.writeFileSync(
        path.join(dir, `${id}.json`),
        JSON.stringify({
          stills: stills.map(({ t }) => ({
            t,
            sees: "a box on a dark ground",
          })),
          failures: [],
        }),
      );
  }
  runStage("gates/gates.mjs", run);
}
