// measure.mjs on a reference video: the motion it reports and the frames
// around each cut it keeps as reference images.
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { candidates, fixture, node } from "./style-lib.mjs";

function measured(config, extra = {}) {
  const { run, docs, env } = fixture();
  fs.writeFileSync(path.join(docs, "talk.mp4"), "mp4");
  env.EXPLAINER_VIDEO_FAKE_VIDEO = JSON.stringify({ "talk.mp4": config });
  Object.assign(env, extra);
  const r = node("measure.mjs", [run, path.join(docs, "talk.mp4")], env);
  return { r, run, docs, env };
}

test("a video's cut rate, blur at cuts and grain are measured into candidates", () => {
  const { r, run } = measured({
    duration: 6,
    cuts: [2, 4],
    blur: 0.7,
    grain: 0.5,
  });
  assert.equal(r.status, 0, r.stderr);
  const m = candidates(run).motion;
  assert.equal(m.cutsPerMinute, 20);
  assert.ok(m.blurAtCuts > 0.4 && m.blurAtCuts < 1, `blur ${m.blurAtCuts}`);
  assert.ok(Math.abs(m.grain - 0.5) < 0.15, `grain ${m.grain}`);
  assert.match(
    r.stdout,
    /^style motion talk\.mp4: 20 cuts\/min · blur 0\.\d+ · grain 0\.\d+$/m,
  );
});

test("a sharp, clean video measures no blur and no grain", () => {
  const { r, run } = measured({ duration: 6, cuts: [2, 4] });
  assert.equal(r.status, 0, r.stderr);
  const m = candidates(run).motion;
  assert.equal(m.blurAtCuts, 0);
  assert.equal(m.grain, 0);
});

test("the frames before, at and after two cuts join the reference images, twelve at most", () => {
  const { r, run } = measured(
    { duration: 6, cuts: [2, 4] },
    { EXPLAINER_VIDEO_FAKE_FRAMES: "15" },
  );
  assert.equal(r.status, 0, r.stderr);
  const names = candidates(run).images.map((i) => i.name);
  for (const cut of [1, 2])
    for (const w of ["before", "at", "after"])
      assert.ok(names.includes(`talk-cut${cut}-${w}.png`), names.join());
  assert.equal(names.length, 12);
  const refs = fs.readdirSync(path.join(run, "style-draft", "refs")).sort();
  assert.deepEqual(refs, names.slice().sort());
});

test("a source that is not a video reports no motion", () => {
  const { run, docs, env } = fixture();
  fs.writeFileSync(path.join(docs, "deck.pdf"), "pdf");
  const r = node("measure.mjs", [run, path.join(docs, "deck.pdf")], env);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(candidates(run).motion, undefined);
  assert.doesNotMatch(r.stdout, /style motion/);
});
