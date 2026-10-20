// The push camera: the grammar's camera family and knobs, a scene's `camera`
// cue, the push-in the composer draws on it, and the compile and render checks
// that bar a `camera` key the profile or the component does not allow.
import { test } from "node:test";
import assert from "node:assert/strict";
import { checkScenes } from "../../skills/explainer-video/scripts/lib/allowed.mjs";
import {
  grammar,
  validate,
} from "../../skills/explainer-video/scripts/lib/style.mjs";
import {
  VISUALS,
  cameraCue,
  checkVisual,
} from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { SCRIPT } from "./scene-file.mjs";
import { fixture, profiled, read, skill, stage } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const odd = (g) => ({ ...claude, name: "odd", grammar: g });

const said = [
  "It reads the issue.",
  "It writes a failing test.",
  "Then the code makes it pass.",
];
const cards = (extra = {}, items) => ({
  component: "cards",
  props: {
    items: items ?? [
      { at: 1, label: "Input", value: "issue" },
      { at: 2, label: "First", value: "test", on: "failing test" },
      { at: 3, label: "Then", value: "code" },
    ],
  },
  ...extra,
});

test("a profile with no camera field pushes in by 1.06 over 0.8 s, and its knobs are bounded", () => {
  assert.deepEqual(grammar(claude).camera, {
    family: "push",
    scale: 1.06,
    duration: 0.8,
  });
  assert.deepEqual(grammar(odd({ camera: { scale: 1.1 } })).camera, {
    family: "push",
    scale: 1.1,
    duration: 0.8,
  });
  assert.equal(grammar(odd({ camera: "locked" })).camera.family, "locked");
  assert.throws(
    () => validate(odd({ camera: { duration: 3 } })),
    /grammar\.camera\.duration 3 is outside 0\.4 to 1\.6/,
  );
  assert.throws(
    () => validate(odd({ camera: "orbit" })),
    /grammar\.camera orbit is not push or locked/,
  );
  assert.doesNotThrow(() => validate(odd({ bans: ["camera"] })));
});

test("a scene's camera beat is its `camera` cue, else the cue of its last revealed item", () => {
  assert.deepEqual(cameraCue(cards(), said), { at: 3 });
  // an item that lands on a later word of the same sentence is the last
  const items = [
    { at: 2, label: "A", value: "a", on: "failing test" },
    { at: 2, label: "B", value: "b", on: "writes" },
    { at: 1, label: "C", value: "c" },
  ];
  assert.deepEqual(cameraCue(cards({}, items), said), {
    at: 2,
    on: "failing test",
  });
  assert.deepEqual(cameraCue(cards({ camera: { at: 2 } }), said), { at: 2 });
});

test("a `camera` key is a cue the scene says, and nothing else", () => {
  assert.doesNotThrow(() =>
    checkVisual(cards({ camera: { at: 2, on: "failing test" } }), said),
  );
  assert.throws(
    () => checkVisual(cards({ camera: { at: 2, on: "passing test" } }), said),
    /on "passing test" is not said in sentence 2/,
  );
  assert.throws(
    () => checkVisual(cards({ camera: { at: 4 } }), said),
    /at 4 is not a sentence \(1 to 3\)/,
  );
  assert.throws(
    () => checkVisual(cards({ camera: { at: 1, scale: 1.1 } }), said),
    /camera has no prop scale \(at, on\)/,
  );
  assert.throws(
    () => checkVisual(cards({ camera: 2 }), said),
    /camera is not a JSON object/,
  );
});

test("a component that draws its own camera refuses a `camera` key", () => {
  VISUALS.title.ownCamera = true;
  try {
    const title = { component: "title", props: { title: "T" } };
    assert.doesNotThrow(() => checkVisual(title, said));
    assert.throws(
      () => checkVisual({ ...title, camera: { at: 1 } }, said),
      /title draws its own camera, so it takes no camera key/,
    );
  } finally {
    delete VISUALS.title.ownCamera;
  }
});

// A scene's file for `visual`, its timing a word every half second.
const timing = {
  duration: 8,
  slot: 8,
  sentences: [0, 2, 4],
  words: Array.from({ length: 16 }, (_, i) => i * 0.5),
};
const drawn = (visual, profile = claude) =>
  sceneFile({ id: "a", narration: said, visual }, timing, profile, {
    backend: {},
    seam: {},
  });
const push = (html) => {
  const m = html.match(
    /tl\.fromTo\('[^']*\.camera', (\{.*?\}), (\{.*?\}), ([\d.]+)\);/,
  );
  return m && [JSON.parse(m[1]), JSON.parse(m[2]), +m[3]];
};
const labels = (html) =>
  [...html.matchAll(/addLabel\("(camera:\w+)", ([\d.]+)\)/g)].map((m) => [
    m[1],
    +m[2],
  ]);

test("a scene with no camera key pushes in to land on its last item's cue", async () => {
  const html = await drawn(cards());
  assert.deepEqual(push(html), [
    { scale: 1 },
    { scale: 1.06, duration: 0.8, ease: "power3.out" },
    3.2,
  ]);
  assert.deepEqual(labels(html), [
    ["camera:start", 3.2],
    ["camera:end", 4],
  ]);
  // the push is on its own element, so the seam on `.content` keeps its start
  assert.match(html, /<div class="camera">/);
});

test("a camera key moves the push to its cue, an `on` phrase to its first spoken word", async () => {
  const at2 = await drawn(cards({ camera: { at: 2 } }));
  assert.deepEqual(labels(at2), [
    ["camera:start", 1.2],
    ["camera:end", 2],
  ]);
  const on = await drawn(cards({ camera: { at: 2, on: "failing test" } }));
  assert.deepEqual(labels(on), [
    ["camera:start", 2.7],
    ["camera:end", 3.5],
  ]);
  // a cue under one push duration into the scene runs the push from 0
  const early = await drawn(cards({ camera: { at: 1 } }));
  assert.deepEqual(labels(early), [
    ["camera:start", 0],
    ["camera:end", 0.8],
  ]);
});

test("the locked family, a camera ban and a component with its own camera compose no push-in", async () => {
  for (const [why, profile, visual] of [
    ["locked", odd({ camera: "locked" }), cards()],
    ["banned", odd({ bans: ["camera"] }), cards()],
  ]) {
    const html = await drawn(visual, profile);
    assert.equal(push(html), null, why);
    assert.deepEqual(labels(html), [], why);
  }
  VISUALS.cards.ownCamera = true;
  try {
    assert.equal(push(await drawn(cards())), null, "own camera");
  } finally {
    delete VISUALS.cards.ownCamera;
  }
});

test("a camera key a profile does not draw is refused, banned or locked", () => {
  const scene = { id: "a", visual: cards({ camera: { at: 1 } }) };
  assert.doesNotThrow(() => checkScenes(claude, [scene]));
  assert.throws(
    () => checkScenes(odd({ bans: ["camera"] }), [scene]),
    /scene a: camera is banned by style profile odd/,
  );
  assert.throws(
    () => checkScenes(odd({ camera: "locked" }), [scene]),
    /scene a: camera key needs the push family: style profile odd's camera family is locked/,
  );
  // no camera key, no finding
  assert.doesNotThrow(() =>
    checkScenes(odd({ bans: ["camera"] }), [{ id: "a", visual: cards() }]),
  );
});

test("compile refuses a camera key a profile bans", () => {
  const text = SCRIPT.replace("style: claude-code", "style: plain").replace(
    '{ "component": "title"',
    '{ "camera": { "at": 1 }, "component": "title"',
  );
  assert.notEqual(text, SCRIPT, "the fixture scene has a title visual");
  const fx = fixture(text);
  profiled(fx, "plain", { grammar: { bans: ["camera"] } });
  const r = stage(fx, "script/compile.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^compile: hook: camera is banned by style profile plain$/m,
  );
});
