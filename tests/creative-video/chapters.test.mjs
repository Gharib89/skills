// The chapter join (render/chapters.mjs) against the fake backend's concat,
// mux and ffprobe, and the delivery check of its chapter marks.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import * as fake from "./fake-backend.mjs";
import {
  chapterCheck,
  joinChapters,
} from "../../skills/creative-video/scripts/render/chapters.mjs";

const CHAPTERS = [
  { start: 0, end: 4, title: "Why" },
  { start: 4, end: 10.5, title: "How" },
];

function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-chapters-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  process.env.CREATIVE_VIDEO_FAKE_LOG = path.join(dir, "calls.jsonl");
  const part = (name, duration) => {
    const f = path.join(dir, name);
    fs.writeFileSync(
      f,
      JSON.stringify({ width: 1920, height: 1080, fps: 30, duration }),
    );
    return f;
  };
  return {
    dir,
    parts: [part("why.mp4", 4), part("how.mp4", 6.5)],
    calls: () =>
      fs
        .readFileSync(process.env.CREATIVE_VIDEO_FAKE_LOG, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l)),
  };
}

test("the parts join by stream copy, the narration and chapters mux once, and the joined file is removed", async (t) => {
  const fx = fixture(t);
  const joined = path.join(fx.dir, "joined.mp4");
  const output = path.join(fx.dir, "demo.mp4");
  await joinChapters(fake, {
    parts: fx.parts,
    joined,
    audio: path.join(fx.dir, "narration.wav"),
    chapters: CHAPTERS,
    output,
  });
  assert.deepEqual(
    fx.calls().map((c) => c.call),
    ["concat", "mux"],
  );
  assert.ok(!fs.existsSync(joined), "the joined file was left behind");
  const probe = await fake.ffprobe(output);
  assert.equal(probe.format.duration, "10.5");
  assert.ok(probe.streams.some((s) => s.codec_type === "audio"));
  assert.deepEqual(chapterCheck(CHAPTERS, probe.chapters), [
    "chapters",
    "2 chapters (0.00 s Why, 4.00 s How)",
    "2 (0.00 s Why, 4.00 s How)",
    true,
  ]);
});

test("a mux that fails still removes the joined file", async (t) => {
  const fx = fixture(t);
  const joined = path.join(fx.dir, "joined.mp4");
  const failing = {
    ...fake,
    mux: async () => {
      throw new Error("ffmpeg: mux failed");
    },
  };
  await assert.rejects(
    joinChapters(failing, {
      parts: fx.parts,
      joined,
      audio: path.join(fx.dir, "narration.wav"),
      chapters: CHAPTERS,
      output: path.join(fx.dir, "demo.mp4"),
    }),
    /mux failed/,
  );
  assert.ok(!fs.existsSync(joined));
});

const probed = (marks) =>
  marks.map(([start, title]) => ({
    start_time: String(start),
    tags: { title },
  }));

test("a chapter mark within a frame of its start passes; one further off, retitled or missing fails", () => {
  assert.equal(
    chapterCheck(
      CHAPTERS,
      probed([
        [0, "Why"],
        [4.03, "How"],
      ]),
    )[3],
    true,
  );
  for (const marks of [
    [
      [0, "Why"],
      [4.04, "How"],
    ],
    [
      [0, "Why"],
      [4, "What"],
    ],
    [[0, "Why"]],
  ])
    assert.equal(chapterCheck(CHAPTERS, probed(marks))[3], false);
  assert.deepEqual(chapterCheck(CHAPTERS), [
    "chapters",
    "0 chapters",
    "2 (0.00 s Why, 4.00 s How)",
    false,
  ]);
});
