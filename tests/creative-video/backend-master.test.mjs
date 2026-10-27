// The real backend's finishing tools, read by the real ffmpeg: a 3 s clip with
// a quiet tone normalised to -14 LUFS under a -1.5 dBTP peak with its video
// stream copied and its audio AAC at 48 kHz, its loudness measured and its
// poster frame taken. Skipped where ffmpeg is not on PATH.
import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  ffprobe,
  loudness,
  loudnorm,
  poster,
} from "../../skills/creative-video/scripts/lib/backend/media.mjs";

const has = spawnSync("ffmpeg", ["-version"]).status === 0;

test(
  "loudnorm brings a quiet clip to the target and copies its video; poster takes one frame",
  { skip: !has && "ffmpeg is not on PATH" },
  async (t) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-master-"));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const src = path.join(dir, "src.mp4");
    const made = spawnSync("ffmpeg", [
      ...["-v", "error", "-y", "-f", "lavfi", "-i", "color=c=red:s=64x64:r=30"],
      ...["-f", "lavfi", "-i", "sine=frequency=300:sample_rate=24000"],
      ...["-t", "3", "-af", "volume=-30dB", "-c:v", "libx264", src],
    ]);
    assert.equal(made.status, 0, made.stderr?.toString());
    const out = path.join(dir, "out.mp4");
    await loudnorm(src, out, { lufs: -14, peak: -1.5 });
    const { lufs, peak } = await loudness(out);
    assert.ok(Math.abs(lufs + 14) < 1, `${lufs} LUFS`);
    assert.ok(peak <= -1.0, `${peak} dBTP`);
    const probe = await ffprobe(out);
    const audio = probe.streams.find((s) => s.codec_type === "audio");
    assert.equal(audio.codec_name, "aac");
    assert.equal(audio.sample_rate, "48000");
    assert.equal(
      probe.streams.find((s) => s.codec_type === "video").codec_name,
      "h264",
    );
    const png = path.join(dir, "poster.png");
    await poster(out, 1.5, png);
    assert.equal(fs.readFileSync(png).toString("ascii", 1, 4), "PNG");
  },
);
