// The `diagram` component drawn: each node and link rises on its own cue, a
// link's arrow strokes on, and packets run along a link on the scene's paused
// timeline, repeating to the scene's end and no further, so a packet's place
// is a function of timeline time. Right to left, the layout mirrors.
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const said = [
  "The client sends a request.",
  "The server reads the cache.",
  "Then it answers the client.",
];
const timing = {
  duration: 8,
  slot: 8,
  sentences: [0, 2, 4.5],
  words: Array.from({ length: 15 }, (_, i) => +(i * 0.3).toFixed(6)),
};
const visual = {
  component: "diagram",
  props: {
    nodes: [
      { id: "client", at: 1, label: "Client" },
      { id: "server", at: 2, label: "Server" },
      { id: "cache", at: 2, on: "the cache", label: "Cache", note: "redis" },
    ],
    links: [
      { from: "client", to: "server", at: 2, packets: 2 },
      { from: "server", to: "cache", at: 2, on: "the cache" },
    ],
  },
};
const drawn = (dir = "ltr") =>
  sceneFile({ id: "a", narration: said, visual }, timing, claude, {
    backend: {},
    seam: {},
    dir,
  });
// Each tween the scene's script puts on its timeline, `[selector, from, to,
// time]`, run against a stub GSAP.
const tweens = (html) => {
  const out = [];
  const tl = {
    fromTo: (sel, from, to, t) =>
      out.push([sel.replace('[data-composition-id="a"] ', ""), from, to, t]),
    progress: () => {},
    duration: () => 0,
    time: () => {},
  };
  vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], {
    gsap: { timeline: () => tl },
    window: { __stills: true },
  });
  return out;
};
const first = (all, sel) => all.find(([s]) => s === sel);

test("each node and link rises on its own cue, the arrow stroked on", async () => {
  const all = tweens(await drawn());
  // "the cache" is the 9th and 10th spoken words, 2.4 s in
  assert.deepEqual(
    [".n0", ".n1", ".n2", ".l0", ".l1"].map((s) => first(all, s)[3]),
    [0, 2, 2.4, 2, 2.4],
  );
  const draw = all.find(
    ([s, from]) => s === ".l1" && "strokeDashoffset" in from,
  );
  assert.deepEqual(
    [draw[1].strokeDashoffset, draw[2].strokeDashoffset],
    [1, 0],
  );
});

test("packets run their link on the timeline, repeating to the scene's end and no further", async () => {
  const all = tweens(await drawn());
  const packets = all.filter(([s]) => /^\.k0-\d$/.test(s));
  assert.equal(packets.length, 2);
  for (const [, from, to, t] of packets) {
    assert.equal(t, 2);
    assert.equal(to.ease, "none");
    // a finite repeat: never forever, never past the scene's end by a trip
    assert.ok(Number.isInteger(to.repeat) && to.repeat >= 0);
    const end = t + to.delay + to.duration * (to.repeat + 1);
    assert.ok(end >= timing.duration && end < timing.duration + to.duration);
    // it runs from the client towards the server
    assert.ok(to.x > from.x);
  }
  // the second packet leaves half a trip after the first
  const [a, b] = packets.map(([, , to]) => to);
  assert.equal(+(b.delay - a.delay).toFixed(2), +(a.duration / 2).toFixed(2));
  // the link without packets draws none
  assert.ok(!all.some(([s]) => /^\.k1-/.test(s)));
  // a packet is moved by the timeline alone: nothing reads the clock
  assert.doesNotMatch(
    await drawn(),
    /Date\.now|performance\.now|requestAnimationFrame|setInterval|animation:/,
  );
});

test("right to left, the diagram mirrors: the first node at the right, packets running right to left", async () => {
  const ltr = await drawn();
  const rtl = await drawn("rtl");
  const left = (html, i) =>
    +html.match(new RegExp(`class="node n${i}" style="left: ([\\d.]+)px`))[1];
  assert.ok(left(ltr, 0) < left(ltr, 1));
  assert.ok(left(rtl, 0) > left(rtl, 1));
  const [, from, to] = tweens(rtl).find(([s]) => s === ".k0-0");
  assert.ok(to.x < from.x);
  assert.match(rtl, /<div class="content" dir="rtl">/);
  assert.doesNotMatch(rtl, /row-reverse|dir="ltr"/);
  // a rich component: no push-in on its camera
  assert.doesNotMatch(rtl, /class="camera"/);
});
