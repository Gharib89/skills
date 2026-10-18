// The render stage's narration: the scenes' WAVs joined into one 16-bit mono
// file at `file`, the hold as silence at its end. `fail(why)` stops the run.
import fs from "node:fs";
import path from "node:path";
import { HOLD } from "../lib/length.mjs";

export function joinNarration({ run, voice, file, fail }) {
  const parts = voice.scenes.map((v) => {
    const b = fs.readFileSync(path.join(run, v.audio));
    if (
      b.toString("ascii", 0, 4) !== "RIFF" ||
      b.readUInt16LE(22) !== 1 ||
      b.readUInt16LE(34) !== 16
    )
      fail(`${v.audio} is not 16-bit mono PCM: run the voice stage again`);
    return {
      rate: b.readUInt32LE(24),
      data: b.subarray(44, 44 + b.readUInt32LE(40)),
    };
  });
  const rate = parts[0].rate;
  if (parts.some((p) => p.rate !== rate))
    fail("the scenes' WAVs differ in sample rate: run the voice stage again");
  const data = Buffer.concat([
    ...parts.map((p) => p.data),
    Buffer.alloc(Math.round(HOLD * rate) * 2),
  ]);
  const h = Buffer.alloc(44);
  h.write("RIFF", 0, "ascii");
  h.writeUInt32LE(36 + data.length, 4);
  h.write("WAVEfmt ", 8, "ascii");
  h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20);
  h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24);
  h.writeUInt32LE(rate * 2, 28);
  h.writeUInt16LE(2, 32);
  h.writeUInt16LE(16, 34);
  h.write("data", 36, "ascii");
  h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(file, Buffer.concat([h, data]));
  return {
    rate,
    pcm: new Int16Array(data.buffer, data.byteOffset, data.length / 2),
  };
}
