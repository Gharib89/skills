// The narration join (render/narration.mjs): the scenes' WAVs joined into one,
// each padded with silence to its frames on the grid.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  joinNarration,
  wavSeconds,
} from "../../skills/creative-video/scripts/render/narration.mjs";

// A 16-bit mono WAV of `n` samples at `rate`, every sample `value`.
function wav(file, n, rate = 24000, value = 1000) {
  const h = Buffer.alloc(44);
  h.write("RIFF", 0, "ascii");
  h.writeUInt32LE(36 + n * 2, 4);
  h.write("WAVEfmt ", 8, "ascii");
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20);
  h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24);
  h.writeUInt32LE(rate * 2, 28);
  h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34);
  h.write("data", 36, "ascii");
  h.writeUInt32LE(n * 2, 40);
  const data = Buffer.alloc(n * 2);
  for (let i = 0; i < n; i++) data.writeInt16LE(value, i * 2);
  fs.writeFileSync(file, Buffer.concat([h, data]));
}

const fail = (why) => {
  throw new Error(why);
};

const run = () => fs.mkdtempSync(path.join(os.tmpdir(), "creative-narration-"));

test("the scenes join in order, each padded with silence to its frames", (t) => {
  const dir = run();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  // At 24 kHz and 30 fps a frame is 800 samples.
  wav(path.join(dir, "a.wav"), 1000, 24000, 1000);
  wav(path.join(dir, "b.wav"), 1600, 24000, 2000);
  const file = path.join(dir, "narration.wav");
  const voice = { scenes: [{ audio: "a.wav" }, { audio: "b.wav" }] };
  const { rate, pcm } = joinNarration({
    run: dir,
    voice,
    frames: [2, 3],
    file,
    fail,
  });
  assert.equal(rate, 24000);
  assert.equal(pcm.length, 5 * 800);
  assert.ok(pcm.subarray(0, 1000).every((s) => s === 1000));
  assert.ok(pcm.subarray(1000, 1600).every((s) => s === 0));
  assert.ok(pcm.subarray(1600, 3200).every((s) => s === 2000));
  assert.ok(pcm.subarray(3200).every((s) => s === 0));
  const b = fs.readFileSync(file);
  assert.equal(b.toString("ascii", 0, 4), "RIFF");
  assert.equal(b.readUInt32LE(24), 24000);
  assert.equal(b.readUInt32LE(40), 5 * 800 * 2);
  assert.equal(b.length, 44 + 5 * 800 * 2);
  assert.equal(wavSeconds(dir, "narration.wav", fail), 5 / 30);
});

test("scenes of two sample rates stop the join", (t) => {
  const dir = run();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  wav(path.join(dir, "a.wav"), 800, 24000);
  wav(path.join(dir, "b.wav"), 800, 16000);
  assert.throws(
    () =>
      joinNarration({
        run: dir,
        voice: { scenes: [{ audio: "a.wav" }, { audio: "b.wav" }] },
        frames: [1, 1],
        file: path.join(dir, "narration.wav"),
        fail,
      }),
    /differ in sample rate: run the voice stage again/,
  );
  assert.ok(!fs.existsSync(path.join(dir, "narration.wav")));
});

test("a scene file that is no 16-bit mono WAV is refused by name", (t) => {
  const dir = run();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  fs.writeFileSync(path.join(dir, "bad.wav"), Buffer.alloc(64));
  assert.throws(
    () => wavSeconds(dir, "bad.wav", fail),
    /^Error: bad\.wav is not 16-bit mono PCM: run the voice stage again$/,
  );
});
