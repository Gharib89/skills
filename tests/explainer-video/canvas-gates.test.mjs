// What the layout gate makes of a canvas scene: the camera windows its script
// marks are read as the events gate reads them off a real timeline, text the
// camera carries is not judged while it moves, and a card the camera is not on
// (dimmed) is never judged at all.
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { sceneEvents } from "../../skills/explainer-video/scripts/gates/events.mjs";
import { readable } from "../../skills/explainer-video/scripts/lib/layout.mjs";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const said = ["One thing.", "Another thing.", "A last thing."];
const timing = {
  duration: 10,
  slot: 10,
  sentences: [0, 2, 5],
  words: Array.from({ length: 9 }, (_, i) => i),
};
const visual = {
  component: "canvas",
  props: {
    items: [
      { at: 1, title: "A", body: "a" },
      { at: 2, title: "B", body: "b" },
      { at: 3, title: "C", body: "c" },
    ],
  },
};

// The camera windows the scene's script marks, as backend.events reads them:
// every `camera:start<n>` with its `camera:end<n>`.
async function windows() {
  const html = await sceneFile(
    { id: "a", narration: said, visual },
    timing,
    claude,
    { backend: {}, seam: {} },
  );
  const labels = {};
  const tl = {
    fromTo: () => {},
    set: () => {},
    addLabel(name, at) {
      labels[name] = at;
      return this;
    },
    progress: () => {},
    duration: () => 0,
    time: () => {},
  };
  vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], {
    gsap: { timeline: () => tl },
    window: {},
  });
  return Object.keys(labels)
    .map((k) => k.match(/^camera:start(\d*)$/))
    .filter((m) => m && `camera:end${m[1]}` in labels)
    .map((m) => [labels[m[0]], labels[`camera:end${m[1]}`]]);
}

test("the gates read one camera window per travel, the overview's last", async () => {
  const w = await windows();
  // to item 2 and item 3 on their cues, then the overview
  assert.equal(w.length, 3);
  assert.deepEqual([w[0][1], w[1][1]], [2, 5]);
  assert.ok(w[2][0] > 5 && w[2][1] <= timing.duration);
});

test("text the camera carries is not judged while it moves, and is once it settles", async () => {
  const w = await windows();
  const start = 20;
  const { moving } = sceneEvents(
    { a: { camera: w, seams: [], ends: [], tweens: [] } },
    [{ id: "a", start }],
  );
  const shown = { scene: "a", opacity: 1, blur: 0 };
  for (const [from, to] of w) {
    const mid = start + (from + to) / 2;
    assert.equal(moving("a", mid), true);
    assert.equal(readable(shown, mid, moving), false);
    // settled: the frame the window ends on, and a moment on
    assert.equal(readable(shown, start + to, moving), true);
  }
  assert.equal(readable(shown, start + 0.5, moving), true);
});

test("a card the camera is not on reads as unreadable to the layout gate", () => {
  const dimmed = { scene: "a", opacity: 0.3, blur: 0 };
  assert.equal(
    readable(dimmed, 20, () => false),
    false,
  );
});
