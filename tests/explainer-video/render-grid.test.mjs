// The frame grid (render/grid.mjs): every scene's duration is whole frames, its
// WAV padded with silence to match, and every time written truncated, because
// HyperFrames renders ceil(duration x fps) frames and a time rounded up by a
// hair costs a whole extra frame.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { FPS } from "../../skills/explainer-video/scripts/render/compose.mjs";
import {
  frames,
  gridScenes,
  padToFrames,
  written,
} from "../../skills/explainer-video/scripts/render/grid.mjs";
import { wavSeconds } from "../../skills/explainer-video/scripts/render/narration.mjs";

test("a duration rounds up to whole frames, float noise aside", () => {
  assert.equal(frames(1 / FPS), 1);
  assert.equal(frames(1.01 / FPS), 2);
  assert.equal(frames(3149 / FPS + 1e-12), 3149);
  assert.equal(frames(3149.00001 / FPS), 3149);
  assert.equal(frames(3149.5 / FPS), 3150);
});

test("a time is written truncated, so HyperFrames counts the frames it names", () => {
  assert.equal(written(3149.00001), 104.966666);
  assert.equal(Math.ceil(written(3149.00001) * FPS), 3149);
  // 2 frames is 0.0666...: rounding to 6 places would write 0.066667, which
  // HyperFrames reads as 2.00001 frames and renders as 3.
  assert.equal(written(2), 0.066666);
  for (let f = 0; f < 5000; f++)
    assert.equal(Math.ceil(written(f) * FPS), f, `frame ${f}`);
});

test("scenes run back to back on the grid, the hold on the last", () => {
  const g = gridScenes([1.0, 0.5, 2.01], 1);
  assert.deepEqual(
    g.map((s) => [s.start, s.frames]),
    [
      [0, 30],
      [30, 15],
      [45, Math.ceil(3.01 * FPS - 1e-4)],
    ],
  );
  assert.equal(g.total, 45 + g[2].frames);
});

test("a scene's PCM is padded with silence to its frames", () => {
  const rate = 24000;
  const data = Buffer.alloc(rate * 2 * 1.01, 1);
  const padded = padToFrames(data, rate, frames(1.01));
  assert.equal(padded.length, (frames(1.01) * rate * 2) / FPS);
  assert.deepEqual(padded.subarray(0, data.length), data);
  assert.ok(padded.subarray(data.length).every((b) => b === 0));
});

test("a PCM already whole frames, or longer, gains no silence and is cut to them", () => {
  const rate = 24000;
  const exact = Buffer.alloc((3 * rate * 2) / FPS, 1);
  assert.deepEqual(padToFrames(exact, rate, 3), exact);
  assert.equal(padToFrames(exact, rate, 2).length, (2 * rate * 2) / FPS);
});

test("one scene is the whole grid, the hold on it", () => {
  const g = gridScenes([1.0], 1);
  assert.deepEqual([g[0].start, g[0].frames, g.total], [0, 60, 60]);
});

test("a scene is sized from its WAV, not the voice stage's rounded seconds", () => {
  // 24010 samples at 24 kHz is 1.000417 s, stored as 1.000: 30 frames would cut
  // 10 samples; the WAV's own length takes 31.
  const rate = 24000;
  const h = Buffer.alloc(44);
  h.writeUInt32LE(rate, 24);
  h.writeUInt32LE(24010 * 2, 40);
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wav-seconds-"));
  const file = path.join(dir, "s.wav");
  fs.writeFileSync(file, Buffer.concat([h, Buffer.alloc(24010 * 2)]));
  try {
    assert.equal(frames(wavSeconds(file)), 31);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
