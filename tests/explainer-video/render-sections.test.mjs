// The render stage on a video in sections: each section rendered video only
// and cached on its own, the parts joined by stream copy, narration and score
// muxed once with a chapter mark per section.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { LAYOUT, sectionFile } from "./sections-lib.mjs";
import { calls, fixture, read, render } from "./render-lib.mjs";

const OPENERS = ["one", "two", "three"];
const parts = (fx) => calls(fx).filter((c) => !c.args.includes("png-sequence"));
const start = (fx, id) =>
  JSON.parse(read(fx.dir, "timeline.json")).scenes.find((s) => s.id === id)
    .start;

test("a sectioned video renders each section on its own, video only, then joins and muxes once", () => {
  const fx = fixture(sectionFile());
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);

  const sections = parts(fx);
  assert.deepEqual(
    sections.map((c) => path.relative(fx.dir, c.cwd)),
    [1, 2, 3].map((n) => path.join(".cache", "sections", String(n))),
  );
  assert.deepEqual(
    sections.map((c) => c.hosts),
    [
      ["hook", "why", "one", "one-a", "one-b"],
      ["two", "two-a", "two-b"],
      ["three", "three-a", "three-b", "recap", "bye"],
    ],
  );
  // The audio is the joined file's one mux, never a section's.
  for (const n of [1, 2, 3])
    assert.ok(
      !read(fx.dir, ".cache", "sections", String(n), "index.html").includes(
        "<audio",
      ),
    );
  assert.match(
    read(fx.dir, "composition", "index.html"),
    /<audio id="narration"/,
  );
  // The critic holds the first render, so the join and mux ran again on the
  // second, every section cached.
  assert.equal(calls(fx, "concat").at(-1).parts.length, 3);
  assert.equal(calls(fx, "mux").length, calls(fx, "concat").length);
  assert.match(r.out, /video 3\/3 sections cached/);
});

test("the delivered MP4 carries one chapter mark per section, each after the first at its opener's first frame", () => {
  const fx = fixture(sectionFile());
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const mp4 = JSON.parse(read(fx.dir, "out", "demo.mp4"));
  // The first chapter starts at 0, the hook and context being its section's:
  // an MP4 cannot start its first chapter later (measured with ffmpeg).
  assert.ok(start(fx, OPENERS[0]) > 0);
  assert.deepEqual(
    mp4.chapters.map((c) => [c.title, c.start]),
    OPENERS.map((id, k) => [`Scene ${id}`, k ? start(fx, id) : 0]),
  );
  // Each chapter ends where the next starts, the last at the video's end.
  assert.equal(mp4.chapters[0].end, mp4.chapters[1].start);
  assert.equal(mp4.chapters[2].end, mp4.duration);
  assert.match(r.out, /^delivery chapters: pass$/m);
});

test("editing one scene re-renders only its section, the others come from the cache", () => {
  const fx = fixture(sectionFile());
  assert.equal(render(fx).code, 0);
  const before = calls(fx).length;
  const file = path.join(fx.dir, "script.md");
  fs.writeFileSync(
    file,
    fs
      .readFileSync(file, "utf8")
      .replace('"title":"Scene two-a"', '"title":"Scene two-a, changed"'),
  );
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const again = calls(fx)
    .slice(before)
    .filter((c) => !c.args.includes("png-sequence"));
  assert.deepEqual(
    again.map((c) => path.relative(fx.dir, c.cwd)),
    [path.join(".cache", "sections", "2")],
  );
  assert.match(r.out, /video 3\/3 sections cached/);
});

test("a delivery without its chapters fails, and no section stands in the cache", () => {
  const fx = fixture(sectionFile());
  const r = render(fx, { EXPLAINER_VIDEO_FAKE_PROBE: '{"chapters":[]}' });
  assert.equal(r.code, 1);
  assert.match(r.out, /^delivery chapters: fail: 0 chapters vs 3 \(.*\)$/m);
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
  assert.deepEqual(fs.readdirSync(path.join(fx.dir, ".cache", "render")), []);
});

test("a video without sections renders whole, with no chapter check", () => {
  const fx = fixture(sectionFile(LAYOUT.filter((s) => s.role !== "section")));
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(parts(fx).length, 1);
  assert.equal(calls(fx, "concat").length, 0);
  assert.ok(!/delivery chapters/.test(r.out));
});
