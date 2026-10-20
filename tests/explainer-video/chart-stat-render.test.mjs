// The `chart` and `stat` components drawn: the final text is in the markup, and
// the count-up is a tween on the scene's timeline whose text is a function of
// its progress alone, so a seek to one time always gives the same text.
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { countText } from "../../skills/explainer-video/scripts/lib/count.mjs";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const said = [
  "Latency fell to 240 milliseconds.",
  "Then 1,200 requests a second held.",
  "Errors stayed under 0.5 percent.",
];
const timing = {
  duration: 8,
  slot: 8,
  sentences: [0, 2, 4.5],
  words: Array.from({ length: 14 }, (_, i) => i * 0.5),
};
const item = (at, label, value) => ({ at, label, value });
const chart = (items, props = {}) => ({
  component: "chart",
  props: { kind: "bar", items, ...props },
});
const stat = (items) => ({ component: "stat", props: { items } });
const drawn = (visual, dir = "ltr") =>
  sceneFile({ id: "a", narration: said, visual }, timing, claude, {
    backend: {},
    seam: {},
    dir,
  });
// Each count-up tween of the scene's script, run against a stub GSAP.
const counted = (html) => {
  const calls = [];
  const tl = {
    fromTo: (sel, from, to, t) => calls.push({ sel, from, to, t }),
    progress: () => {},
  };
  vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], {
    gsap: { timeline: () => tl },
    window: { __stills: true },
  });
  return calls.filter((c) => c.to.modifiers);
};
const text = (c, p) => c.to.modifiers.textContent(p);

test("countText counts from 0 to the number as written, a function of progress alone", () => {
  assert.equal(countText("1,200", 0), "0");
  assert.equal(countText("1,200", 0.5), "600");
  assert.equal(countText("0.5", 0.5), "0.3");
  for (const w of ["1,200", "1200", "0.5", "1,200.25", "0", "7", "240"])
    assert.equal(countText(w, 1), w);
  for (const p of [0, 0.31, 0.77, 1])
    assert.equal(countText("1,200.5", p), countText("1,200.5", p));
});

test("a stat's numbers sit in the markup as written and count up on their cues", async () => {
  const html = await drawn(
    stat([
      { at: 1, value: "240", label: "ms", on: "240 milliseconds" },
      { at: 2, value: "1,200", label: "per second" },
    ]),
  );
  assert.match(html, /<bdi class="num lat ti">240<\/bdi>/);
  assert.match(html, /<bdi class="num lat ti">1,200<\/bdi>/);
  const [a, b] = counted(html);
  assert.deepEqual(
    [a.sel, b.sel],
    [
      '[data-composition-id="a"] .r0 .num',
      '[data-composition-id="a"] .r1 .num',
    ],
  );
  // "240 milliseconds" is the 4th spoken word of sentence 1; sentence 2 is at 2 s
  assert.deepEqual([a.t, b.t], [1.5, 2]);
  assert.deepEqual([a.from.textContent, a.to.textContent], [0, 1]);
  assert.deepEqual([text(a, 0), text(a, 1)], ["0", "240"]);
  assert.deepEqual([text(b, 0.5), text(b, 1)], ["600", "1,200"]);
  // seeking twice to one time gives equal text
  assert.equal(text(b, 0.37), text(b, 0.37));
  // a rich component: no push-in on its camera
  assert.doesNotMatch(html, /class="camera"/);
});

test("a bar chart draws a bar a number, its height the number's share of the largest", async () => {
  const html = await drawn(
    chart([item(1, "Before", "240"), item(2, "After", "1,200")], {
      unit: "ms",
    }),
  );
  assert.match(html, /class="bar r0" data-line="c0" style="--p:0.2"/);
  assert.match(html, /class="bar r1" data-line="c1" style="--p:1"/);
  assert.match(html, /<span class="unit">ms<\/span>/);
  assert.equal(counted(html).length, 2);
});

test("a line chart puts a point and a segment a number, the first at the reading start", async () => {
  const items = [item(1, "a", "10"), item(2, "b", "20"), item(3, "c", "40")];
  const ltr = await drawn(chart(items, { kind: "line" }));
  const rtl = await drawn(chart(items, { kind: "line" }), "rtl");
  const xs = (html) =>
    [
      ...html.matchAll(/class="pt r\d" data-line="c\d" style="left:([\d.]+)%/g),
    ].map((m) => +m[1]);
  assert.deepEqual(xs(ltr), [0, 50, 100]);
  assert.deepEqual(xs(rtl), [100, 50, 0]);
  assert.equal((ltr.match(/class="seg s\d"/g) ?? []).length, 2);
  assert.equal(counted(ltr).length, 3);
});

test("right to left, bars and stats follow the page's direction, never reversed by hand", async () => {
  for (const visual of [
    chart([item(1, "a", "1"), item(2, "b", "2")]),
    stat(
      [item(1, "a", "1"), item(2, "b", "2")].map(({ at, label, value }) => ({
        at,
        label,
        value,
      })),
    ),
  ]) {
    const html = await drawn(visual, "rtl");
    assert.match(html, /<div class="content" dir="rtl">/);
    assert.doesNotMatch(html, /row-reverse|direction:\s*ltr|dir="ltr"/);
  }
});
