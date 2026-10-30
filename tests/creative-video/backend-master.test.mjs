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
  masterAudio,
  mux,
  poster,
} from "../../skills/creative-video/scripts/lib/backend/media.mjs";

const has = spawnSync("ffmpeg", ["-version"]).status === 0;

// 20 s of a quiet pink-noise bed with a 10 ms square burst at about 0 dBFS
// every 2 s, the shape of a kit's stamp effect: two-pass loudnorm delivered
// it over the -1 dBTP ceiling and 5 LU under the target (ffmpeg 8.0.1).
function transientClip(dir) {
  const src = path.join(dir, "transient.mkv");
  const made = spawnSync("ffmpeg", [
    ...["-v", "error", "-y", "-f", "lavfi", "-i", "color=c=red:s=64x64:r=30"],
    ...[
      "-f",
      "lavfi",
      "-i",
      "anoisesrc=color=pink:amplitude=0.1:seed=1:r=48000",
    ],
    ...["-f", "lavfi", "-i"],
    "aevalsrc='0.99*if(lt(sin(2*PI*1000*t),0),-1,1)*lt(mod(t,2),0.01)':s=48000",
    ...["-filter_complex", "[1:a][2:a]amix=inputs=2:normalize=0[a]"],
    ...["-map", "0:v", "-map", "[a]", "-t", "20"],
    ...["-c:v", "libx264", "-c:a", "pcm_f32le", src],
  ]);
  assert.equal(made.status, 0, made.stderr?.toString());
  return src;
}

// The delivery contract the render checks on the encoded file.
async function delivers(file) {
  const { lufs, peak } = await loudness(file);
  assert.ok(Math.abs(lufs + 14) <= 1, `${lufs} LUFS`);
  assert.ok(peak <= -1.0, `${peak} dBTP`);
}

test(
  "loudnorm holds a mix with sharp transients under the true-peak ceiling and on the loudness target after the AAC encode",
  { skip: !has && "ffmpeg is not on PATH" },
  async (t) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-master-"));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const out = path.join(dir, "out.mp4");
    await loudnorm(transientClip(dir), out, { lufs: -14, peak: -1.5 });
    await delivers(out);
  },
);

test(
  "masterAudio's mix of a sharp-transient clip, muxed as the join does, stays under the ceiling and on the target",
  { skip: !has && "ffmpeg is not on PATH" },
  async (t) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-master-"));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const src = transientClip(dir);
    const wav = path.join(dir, "mix.wav");
    await masterAudio(src, wav, { lufs: -14, peak: -1.5, seconds: 20 });
    const out = path.join(dir, "out.mp4");
    await mux({
      video: src,
      audio: wav,
      chapters: [{ start: 0, end: 20, title: "All" }],
      output: out,
    });
    await delivers(out);
  },
);

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

test(
  "masterAudio writes a 48 kHz WAV of exactly the seconds asked, padded or trimmed, at the loudness target",
  { skip: !has && "ffmpeg is not on PATH" },
  async (t) => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-master-"));
    t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
    const src = path.join(dir, "src.mp4");
    const made = spawnSync("ffmpeg", [
      ...["-v", "error", "-y", "-f", "lavfi", "-i", "color=c=red:s=64x64:r=1"],
      ...["-f", "lavfi", "-i", "sine=frequency=300:sample_rate=24000"],
      ...["-t", "3", "-af", "volume=-30dB", "-c:v", "libx264", src],
    ]);
    assert.equal(made.status, 0, made.stderr?.toString());
    for (const seconds of [4, 2]) {
      const wav = path.join(dir, `${seconds}.wav`);
      await masterAudio(src, wav, { lufs: -14, peak: -1.5, seconds });
      const probe = await ffprobe(wav);
      const [audio] = probe.streams;
      assert.equal(audio.codec_name, "pcm_s16le");
      assert.equal(audio.sample_rate, "48000");
      assert.ok(
        Math.abs(+probe.format.duration - seconds) < 0.01,
        `${seconds} s asked, ${probe.format.duration} s written`,
      );
      const { lufs, peak } = await loudness(wav);
      assert.ok(Math.abs(lufs + 14) < 1, `${lufs} LUFS`);
      assert.ok(peak <= -1.0, `${peak} dBTP`);
    }
  },
);
