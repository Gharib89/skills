// The `timeline` and `compare` components drawn: each item reveals on its own
// cue, a `when` shows as written, and right to left both follow the page's
// direction (the first event and the first side at the right).
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const said = [
  "It began as a side project.",
  "Then it shipped to every team.",
  "Now it runs the whole build.",
];
const timing = {
  duration: 8,
  slot: 8,
  sentences: [0, 2, 4.5],
  words: Array.from({ length: 18 }, (_, i) => +(i * 0.3).toFixed(6)),
};
const timeline = (items) => ({ component: "timeline", props: { items } });
const compare = (sides) => ({ component: "compare", props: { sides } });
const drawn = (visual, dir = "ltr") =>
  sceneFile({ id: "a", narration: said, visual }, timing, claude, {
    backend: {},
    seam: {},
    dir,
  });
// The time each selector first tweens on the scene's timeline, run against a
// stub GSAP.
const cued = (html) => {
  const at = {};
  const tl = {
    fromTo: (sel, from, to, t) => {
      const k = sel.replace('[data-composition-id="a"] ', "");
      if (!(k in at)) at[k] = t;
    },
    progress: () => {},
    duration: () => 0,
    time: () => {},
  };
  vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], {
    gsap: { timeline: () => tl },
    window: { __stills: true },
  });
  return at;
};
// The text of every element of `cls`, its tags dropped and entities decoded.
const texts = (html, cls) =>
  [...html.matchAll(new RegExp(`<div class="${cls}">(.*?)</div>`, "g"))].map(
    (m) =>
      m[1]
        .replace(/<[^>]+>/g, "")
        .replaceAll("&quot;", '"')
        .replaceAll("&lt;", "<")
        .replaceAll("&gt;", ">")
        .replaceAll("&amp;", "&"),
  );

const EVENTS = [
  { at: 1, on: "side project", when: "late 2019", label: "Started" },
  { at: 2, when: "Q3 '21 & after", label: "Shipped", note: "every team" },
  { at: 3, when: "Day <1>", label: "Runs the build" },
];

test("a timeline reveals each event on its own cue", async () => {
  const at = cued(await drawn(timeline(EVENTS)));
  // "side project" is the 5th spoken word, 1.2 s in; sentences 2 and 3 start
  // at 2 and 4.5 s
  assert.deepEqual([at[".r0"], at[".r1"], at[".r2"]], [1.2, 2, 4.5]);
});

test("a timeline's when shows exactly as written, never parsed, left to right and right to left", async () => {
  for (const dir of ["ltr", "rtl"]) {
    const html = await drawn(timeline(EVENTS), dir);
    assert.deepEqual(
      texts(html, "when"),
      EVENTS.map((e) => e.when),
    );
    // nothing counts or rewrites it on the timeline
    assert.doesNotMatch(html, /modifiers/);
  }
});

test("a compare reveals each item on its cue, and a side's title with its first item", async () => {
  const at = cued(
    await drawn(
      compare([
        {
          title: "Before",
          items: [
            { at: 1, text: "A side project" },
            { at: 2, on: "every team", text: "Copied by hand" },
          ],
        },
        { title: "After", items: [{ at: 3, text: "Runs the build" }] },
      ]),
    ),
  );
  // "every team" is the 11th spoken word, 3 s in
  assert.deepEqual(
    [at[".s0"], at[".s0 .i0"], at[".s0 .i1"], at[".s1"], at[".s1 .i0"]],
    [0, 0, 3, 4.5, 4.5],
  );
  assert.deepEqual(
    texts(
      await drawn(
        compare([
          { title: "Before", items: [{ at: 1, text: "x" }] },
          { title: "After", items: [{ at: 2, text: "y" }] },
        ]),
      ),
      "stitle",
    ),
    ["Before", "After"],
  );
});

test("right to left, the first event and the first side sit at the reading start, never reversed by hand", async () => {
  const sides = [
    { title: "قبل", items: [{ at: 1, text: "يدوي" }] },
    { title: "بعد", items: [{ at: 2, text: "تلقائي" }] },
  ];
  for (const visual of [timeline(EVENTS), compare(sides)]) {
    const html = await drawn(visual, "rtl");
    assert.match(html, /<div class="content" dir="rtl">/);
    assert.doesNotMatch(html, /row-reverse|direction:\s*ltr|dir="ltr"/);
    // a rich component: no push-in on its camera
    assert.doesNotMatch(html, /class="camera"/);
  }
  const html = await drawn(compare(sides), "rtl");
  assert.ok(html.indexOf("قبل") < html.indexOf("بعد"));
});
