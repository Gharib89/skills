// The `canvas` seam family: a whole video on one map, the camera travelling
// from each scene to the next instead of a zoom-through or a cut. The profile's
// `travel` knob is bounded, a scene starts where it always did (the camera
// travels over the start of the next scene, as a seam does), a scene's own seam
// is a travel or a plain cut, and right to left the map runs leftwards.
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { places } from "../../skills/explainer-video/scripts/render/map.mjs";
import { seamReason } from "../../skills/explainer-video/scripts/lib/allowed.mjs";
import {
  grammar,
  validate,
} from "../../skills/explainer-video/scripts/lib/style.mjs";
import {
  sceneFile,
  stillsPage,
  videoPage,
} from "../../skills/explainer-video/scripts/render/compose.mjs";
import { seamPlan } from "../../skills/explainer-video/scripts/render/seams.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const styled = (seams) => ({ ...claude, grammar: { seams } });
const mapped = styled({ family: "canvas", travel: 0.8 });
const scenes = (n, extra = {}) =>
  Array.from({ length: n }, (_, i) => ({
    role: "point",
    visual: { component: "title", ...(i === 0 && extra) },
  }));

test("the canvas family takes a travel knob in 0.4 to 1.6 s, 0.8 by default", () => {
  assert.equal(grammar(validate(mapped) ?? mapped).seams.travel, 0.8);
  assert.equal(grammar(styled("canvas")).seams.travel, 0.8);
  for (const travel of [0.3, 1.7])
    assert.throws(
      () => validate(styled({ family: "canvas", travel })),
      new RegExp(`grammar.seams.travel ${travel} is outside 0.4 to 1.6`),
    );
  assert.throws(
    () => validate(styled({ family: "canvas", travel: "slow" })),
    /grammar.seams.travel slow is not a number/,
  );
  assert.throws(
    () => validate(styled("map")),
    /grammar.seams map is not velocity or cut or canvas/,
  );
});

test("every scene hands over by a travel of whole frames, the last by none", () => {
  const plan = seamPlan(scenes(3), mapped);
  assert.deepEqual(plan[0].out, {
    move: "travel",
    frames: 24,
    duration: 0.8,
    blur: 0,
  });
  assert.deepEqual(
    plan.map((p) => p.out?.move ?? null),
    ["travel", "travel", null],
  );
  assert.deepEqual(
    plan.map((p) => p.in?.move ?? null),
    [null, "travel", "travel"],
  );
  // the knob sets the travel's length
  const slow = seamPlan(scenes(2), styled({ family: "canvas", travel: 1.5 }));
  assert.equal(slow[0].out.frames, 45);
});

test("a scene may name a travel or a plain cut, never another family's move", () => {
  assert.equal(seamReason(mapped, "travel"), null);
  assert.equal(seamReason(mapped, "cut"), null);
  assert.match(
    seamReason(mapped, "zoom-through"),
    /seam zoom-through is not one of travel, cut/,
  );
  assert.match(seamReason(claude, "travel"), /seam travel is not one of/);
  const plan = seamPlan(scenes(3, { seam: "cut" }), mapped);
  assert.deepEqual(
    plan.map((p) => p.out?.move ?? null),
    [null, "travel", null],
  );
});

// A scene's script run against a stub GSAP: its content tweens and its labels.
const sceneRun = async (seam) => {
  const html = await sceneFile(
    {
      id: "a",
      narration: ["Hi."],
      visual: { component: "title", props: { title: "T" } },
    },
    { duration: 3, slot: 3.8, sentences: [0.1], words: [0.1] },
    mapped,
    { backend: {}, seam },
  );
  const content = [];
  const labels = {};
  const tl = {
    fromTo: (sel, ...rest) => sel.endsWith(".content") && content.push(rest),
    addLabel(name, at) {
      labels[name] = at;
      return this;
    },
    time: () => {},
    duration: () => 0,
  };
  vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], {
    gsap: { timeline: () => tl },
    window: {},
  });
  return { content, labels };
};
const travel = { move: "travel", frames: 24, duration: 0.8, blur: 0 };

test("a scene handed over by a travel moves nothing of its own, and marks the window for the gates", async () => {
  const { content, labels } = await sceneRun({ in: travel, out: travel });
  // the camera carries the scene: its content is never tweened
  assert.deepEqual(content, []);
  const seam = Object.fromEntries(
    Object.entries(labels).filter(([k]) => k.startsWith("seam")),
  );
  assert.deepEqual(seam, {
    "seam:start": 0,
    "seam:end": 0.8,
    "seam:start2": 3,
    "seam:end2": 3.8,
  });
});

// The video page's script run against a stub GSAP: every tween on main.
const FONTS = [];
const video = (profile, dir = "ltr", n = 5, run = 0.8) => {
  // scenes of 3 s whose slot runs `run` s on into the next one
  const sc = Array.from({ length: n }, (_, i) => ({
    id: `s${i}`,
    start: i * 3,
    duration: 3,
    slot: i < n - 1 ? +(3 + run).toFixed(6) : 3,
  }));
  const html = videoPage({
    title: "T",
    profile,
    fonts: FONTS,
    scenes: sc,
    cues: [],
    total: n * 3,
    dir,
  });
  const tweens = [];
  const tl = {
    fromTo: (sel, from, to, at) => tweens.push({ sel, from, to, at }),
    set: (sel, vars, at) => tweens.push({ sel, set: vars, at }),
    addLabel() {
      return this;
    },
  };
  vm.runInNewContext(
    [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1],
    {
      gsap: { timeline: () => tl },
      window: {},
      document: { querySelectorAll: () => [] },
    },
  );
  return { html, tweens: tweens.filter((t) => t.sel === "#world") };
};
const hostAt = (html, id) =>
  [
    ...html.matchAll(
      new RegExp(
        `id="scene-${id}"[^>]*style="[^"]*left: (-?\\d+)px; top: (-?\\d+)px`,
        "g",
      ),
    ),
  ].map((m) => [+m[1], +m[2]])[0];

test("the scenes sit on one map in a world layer, the first at the frame's origin", () => {
  const { html } = video(mapped);
  assert.match(html, /<div id="world"[^>]*>\s*<div id="scene-s0"/);
  assert.deepEqual(hostAt(html, "s0"), [0, 0]);
  // along a row in reading order, a row down at the end of a row, the next
  // row back the way it came, so neighbours in the video are neighbours
  // on the map
  const at = [0, 1, 2, 3, 4].map((i) => hostAt(html, `s${i}`));
  assert.ok(at[1][0] > at[0][0] && at[2][0] > at[1][0] && at[3][0] > at[2][0]);
  assert.equal(at[3][1], 0);
  assert.equal(at[4][1] > 0 && at[4][0] === at[3][0], true);
  assert.equal(at[0][1], at[1][1]);
});

test("the camera travels from each scene to the next over the next scene's start, no scene start moving", () => {
  const { tweens, html } = video(mapped);
  const moves = tweens.filter((t) => t.to);
  assert.deepEqual(
    moves.map((m) => [m.at, m.to.duration]),
    [
      [3, 0.8],
      [6, 0.8],
      [9, 0.8],
      [12, 0.8],
    ],
  );
  // the camera ends each travel on the next scene's place
  for (const [k, m] of moves.entries()) {
    const [left, top] = hostAt(html, `s${k + 1}`);
    assert.deepEqual([m.to.x + 0, m.to.y + 0], [-left + 0, -top + 0]);
  }
  // and the clips keep their starts
  for (const i of [0, 1, 2, 3, 4])
    assert.match(
      html,
      new RegExp(`id="scene-s${i}"[^>]*data-start="${i * 3}"`),
    );
});

test("right to left the map runs leftwards, the first scene at the right of the second", () => {
  const { html, tweens } = video(mapped, "rtl");
  assert.ok(hostAt(html, "s1")[0] < hostAt(html, "s0")[0]);
  const m = tweens.filter((t) => t.to);
  assert.ok(m[0].to.x > 0);
});

test("a plain cut between two scenes jumps the camera, and the stills page has no map", () => {
  const { tweens } = video(mapped, "ltr", 2, 0);
  assert.equal(tweens.length, 1);
  assert.equal(tweens[0].at, 3);
  assert.equal(tweens[0].to, undefined);
  assert.equal(
    stillsPage({
      title: "T",
      profile: mapped,
      fonts: FONTS,
      ids: ["s0"],
    }).includes('id="world"'),
    false,
  );
});

test("the other families draw no world layer", () => {
  assert.equal(video(claude).html.includes('id="world"'), false);
});

test("past four scenes the map turns back along the next row, so neighbours in the video stay neighbours, right to left too", () => {
  const size = { width: 1920, height: 1080 };
  const w = 1920 + 480;
  const h = 1080 + 270;
  // `+ 0` turns the mirrored first column's -0 into 0, which deepEqual tells apart
  const col = (p) => [p.left / w + 0, p.top / h];
  assert.deepEqual(places(6, size, false).map(col), [
    [0, 0],
    [1, 0],
    [2, 0],
    [3, 0],
    [3, 1],
    [2, 1],
  ]);
  assert.deepEqual(places(6, size, true).map(col), [
    [0, 0],
    [-1, 0],
    [-2, 0],
    [-3, 0],
    [-3, 1],
    [-2, 1],
  ]);
});
