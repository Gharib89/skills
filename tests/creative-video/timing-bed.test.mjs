// The bed in the root: sound.json's bed at its level, its volume lane ducking
// it under the words and silencing it in its `out` scenes.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  DUCK,
  bedLane,
  laneAt,
} from "../../skills/creative-video/scripts/render/bed.mjs";
import { SCENES } from "./voice-lib.mjs";
import {
  exec,
  project,
  read,
  readJson,
  timing,
  voiced,
} from "./timing-lib.mjs";

const BED = {
  world: "a kitchen",
  query: "kitchen ambience",
  level: -28,
  out: ["context"],
  source: "openverse:bed-1",
  file: "assets/sounds/bed-1.mp3",
  licence: "CC0-1.0",
};
function withBed(fx, bed = BED) {
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "sound.json"), JSON.stringify({ bed }));
}
// The root's <audio id="bed"> attributes, or undefined.
const bedOf = (fx) => {
  const tag = read(project(fx, "index.html")).match(
    /<audio id="bed"([^>]*)><\/audio>/,
  )?.[1];
  return (
    tag &&
    Object.fromEntries(
      [...tag.matchAll(/ ([\w-]+)(?:="([^"]*)")?/g)].map(([, k, v]) => [
        k,
        v === undefined ? true : v.replaceAll("&quot;", '"'),
      ]),
    )
  );
};

test("the bed plays in the root, looped, at its level, full between the words, ducked under them and silent in its out scenes", () => {
  const fx = voiced(SCENES);
  withBed(fx);
  const t = exec(timing, fx);
  assert.equal(t.code, 0, t.out + t.err);
  const tl = readJson(path.join(fx.dir, "timeline.json"));
  const a = bedOf(fx);
  assert.equal(a.src, "assets/sounds/bed-1.mp3");
  assert.equal(a["data-start"], "0");
  assert.equal(+a["data-duration"], tl.total);
  assert.equal(a["data-volume"], "0.0398");
  assert.equal(a.loop, true);
  const { version, lanes } = JSON.parse(a["data-automation"]);
  assert.equal(version, 1);
  assert.equal(lanes[0].target, "volume");
  const { points } = lanes[0];
  assert.deepEqual(points[0], { t: 0, v: 1 });
  for (const s of tl.scenes)
    for (const w of s.words)
      assert.equal(
        laneAt(points, (w.start + w.end) / 2),
        s.id === "context" ? 0 : DUCK,
        `${s.id} ${w.text}`,
      );
  // The last scene's 1 s hold, after its last word.
  assert.equal(points.at(-1).v, 1);
  assert.equal(points.at(-1).t, tl.total);
});

test("no bed, or a bed sounds.mjs has not filled, puts none in the root", () => {
  const fx = voiced(SCENES);
  assert.equal(exec(timing, fx).code, 0);
  assert.equal(bedOf(fx), undefined);
  withBed(fx, { query: "kitchen ambience", level: -28 });
  assert.equal(exec(timing, fx).code, 0);
  assert.equal(bedOf(fx), undefined);
});

test("an out scene the timeline lacks is refused", () => {
  const fx = voiced(SCENES);
  withBed(fx, { ...BED, out: ["kitchen"] });
  const r = exec(timing, fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^timing: project\/kit\/sound\.json: bed\.out names kitchen, no scene of the timeline/,
  );
});

test("a lane past 512 points merges the word runs over wider gaps", () => {
  const words = Array.from({ length: 1000 }, (_, i) => ({
    text: "word",
    start: i,
    end: i + 0.3,
  }));
  const timeline = {
    total: 1000,
    scenes: [{ id: "one", start: 0, duration: 1000, words }],
  };
  const lane = bedLane(timeline);
  assert.ok(lane.length <= 512, `${lane.length} points`);
  assert.equal(laneAt(lane, 500.15), DUCK);
});

test("out scenes whose silences alone take the lane past 512 points are refused, not merged forever", () => {
  const scenes = Array.from({ length: 260 }, (_, i) => ({
    id: `s${i}`,
    start: i * 10,
    duration: 10,
    words: [{ text: "word", start: i * 10, end: i * 10 + 10 }],
  }));
  const out = scenes.filter((_, i) => i % 2).map((s) => s.id);
  assert.throws(
    () => bedLane({ total: 2600, scenes }, out),
    /^Error: project\/kit\/sound\.json: bed\.out's 130 scene\(s\) take the bed's volume lane past 512 points: silence fewer scenes, or neighbouring ones$/,
  );
});
