// Maintainer only: the run folders real-render.mjs renders and the frame
// comparison it reads the renders with.
import fs from "node:fs";
import path from "node:path";
import { narrator } from "../scripts/lib/narrators.mjs";
import { FPS } from "../scripts/render/grid.mjs";
import { HEIGHT, WIDTH } from "../scripts/render/root.mjs";

const RATE = 24000;

// A mono 16-bit 220 Hz WAV exactly `n` frames long, the narration stand-in.
export function tone(n) {
  const pcm = Buffer.alloc(((n * RATE) / FPS) * 2);
  for (let i = 0; i < pcm.length / 2; i++)
    pcm.writeInt16LE(
      Math.round(3000 * Math.sin((2 * Math.PI * 220 * i) / RATE)),
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

// The run folder `<dir>/<name>` as the voice stage and the agent leave it: one
// scene per `{ id, frames }`, voiced by a tone exactly `frames` long with its
// two words spread over it, and its composition authored. The timing stage
// times it, the render stage renders it.
export function runFolder(dir, name, scenes) {
  const run = path.join(dir, name);
  const comps = path.join(run, "project", "compositions");
  fs.mkdirSync(path.join(run, "voice"), { recursive: true });
  fs.mkdirSync(comps, { recursive: true });
  const narration = (id) => `Scene ${id}.`;
  fs.writeFileSync(
    path.join(run, "script.json"),
    JSON.stringify({
      language: "en",
      scenes: scenes.map(({ id }) => ({ id, narration: [narration(id)] })),
    }),
  );
  const voiced = scenes.map(({ id, frames }, i) => {
    const audio = `voice/${id}.wav`;
    fs.writeFileSync(path.join(run, audio), tone(frames));
    fs.writeFileSync(
      path.join(comps, `${id}.html`),
      composition(id, (i * 137) % 360),
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
    };
  });
  fs.writeFileSync(
    path.join(run, "voice.json"),
    JSON.stringify({
      narrator: narrator(undefined, "en").id,
      language: "en",
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
