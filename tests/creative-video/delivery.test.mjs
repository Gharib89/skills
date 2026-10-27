// Delivery (render/delivery.mjs): the SRT, the manifest, the repo a run folder
// belongs to, the copy into the videos folder, and the facts ffprobe gives.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  deliver,
  repoName,
  srtText,
  videoFacts,
  writeManifest,
} from "../../skills/creative-video/scripts/render/delivery.mjs";

function tmp(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-delivery-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return dir;
}

test("the cues write as numbered SRT blocks with comma milliseconds", () => {
  assert.equal(
    srtText([
      { start: 0, end: 1.5, text: "One two." },
      { start: 3661.0004, end: 3662.25, text: "Three." },
    ]),
    "1\n00:00:00,000 --> 00:00:01,500\nOne two.\n\n" +
      "2\n01:01:01,000 --> 01:01:02,250\nThree.\n",
  );
});

test("the manifest carries the skill's version first, then the facts", (t) => {
  const run = tmp(t);
  writeManifest(run, { slug: "demo", duration: 12.5 });
  const text = fs.readFileSync(path.join(run, "manifest.json"), "utf8");
  assert.deepEqual(Object.keys(JSON.parse(text)), [
    "skill",
    "slug",
    "duration",
  ]);
  assert.match(JSON.parse(text).skill, /^\d+\.\d+\.\d+$/);
  assert.ok(text.endsWith("}\n"));
});

test("outside git a run's repo is the folder holding creative-videos/; in git it is the repo's", (t) => {
  const root = tmp(t);
  const run = path.join(root, "proj", "sub", "creative-videos", "demo");
  fs.mkdirSync(run, { recursive: true });
  assert.equal(repoName(run), "sub");
  const init = spawnSync("git", ["init", "-q", path.join(root, "proj")]);
  assert.equal(init.status, 0, init.stderr?.toString());
  assert.equal(repoName(run), "proj");
});

test("deliver copies the video, its captions and poster under the repo's name", (t) => {
  const root = tmp(t);
  const run = path.join(root, "proj", "creative-videos", "demo");
  const out = path.join(run, "out");
  fs.mkdirSync(out, { recursive: true });
  for (const f of ["demo.mp4", "demo.srt", "poster.png"])
    fs.writeFileSync(path.join(out, f), f);
  const videos = path.join(root, "Videos");
  const to = deliver(run, out, "demo", videos);
  assert.equal(to, path.join(videos, "creative-video", "proj", "demo"));
  assert.deepEqual(fs.readdirSync(to).sort(), [
    "demo.mp4",
    "demo.srt",
    "poster.png",
  ]);
  assert.equal(fs.readFileSync(path.join(to, "demo.srt"), "utf8"), "demo.srt");
});

test("the video's facts come from its stream, the ratio from its size when ffprobe gives none", () => {
  const probe = (extra) => ({
    streams: [
      { codec_type: "audio" },
      {
        codec_type: "video",
        width: 1920,
        height: 1080,
        r_frame_rate: "30000/1001",
        ...extra,
      },
    ],
  });
  assert.deepEqual(videoFacts(probe()), {
    size: "1920x1080",
    fps: 29.97,
    ratio: "16:9",
  });
  assert.equal(
    videoFacts(probe({ display_aspect_ratio: "0:1" })).ratio,
    "16:9",
  );
  assert.equal(
    videoFacts(probe({ display_aspect_ratio: "64:27" })).ratio,
    "64:27",
  );
});
