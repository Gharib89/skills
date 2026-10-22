// The `canvas` component drawn: cards on a map, a camera that travels to each
// item landing on its cue and ends on the overview, every travel marked as a
// camera window so the gates judge no text until it settles, and the tour
// right to left in Arabic.
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import {
  CONTENT,
  W,
  sceneFile,
} from "../../skills/explainer-video/scripts/render/compose.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const said = [
  "It starts at the source.",
  "Then the build runs.",
  "Then it ships to everyone.",
];
const timing = {
  duration: 10,
  slot: 10,
  sentences: [0, 2, 4.5],
  words: Array.from({ length: 18 }, (_, i) => +(i * 0.3).toFixed(6)),
};
const ITEMS = [
  { at: 1, title: "Source", body: "Where the change begins" },
  { at: 2, on: "the build", title: "Build", body: "Compiled and tested" },
  { at: 3, title: "Release", body: "Shipped to every user" },
];
const canvas = (items = ITEMS) => ({ component: "canvas", props: { items } });
const drawn = (visual, dir = "ltr", t = timing) =>
  sceneFile({ id: "a", narration: said, visual }, t, claude, {
    backend: {},
    seam: {},
    dir,
  });
// The script run against a stub GSAP: every tween and every label it makes.
const played = (html) => {
  const tweens = [];
  const labels = {};
  const tl = {
    fromTo: (sel, from, to, at) =>
      tweens.push({
        sel: sel.replace('[data-composition-id="a"] ', ""),
        from,
        to,
        at,
      }),
    set: (sel, vars, at) => tweens.push({ sel: String(sel), set: vars, at }),
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
  return { tweens, labels };
};
const moves = (p) => p.tweens.filter((t) => t.sel === ".cv" && t.to);
const END = (m) => +(m.at + m.to.duration).toFixed(6);

test("the camera lands on each item at its cue and ends on the overview", async () => {
  const p = played(await drawn(canvas()));
  const m = moves(p);
  // the camera starts on item 1; "the build" is the 7th spoken word, 1.8 s in,
  // and sentence 3 starts at 4.5 s
  assert.equal(m.length, 3);
  assert.deepEqual([END(m[0]), END(m[1])], [1.8, 4.5]);
  // then the overview, after the last item has been held a while
  assert.ok(m[2].at >= 4.5 + 0.4);
  assert.ok(END(m[2]) <= timing.duration);
});

test("each travel is a camera window the gates read, the landing the window's end", async () => {
  const p = played(await drawn(canvas()));
  const m = moves(p);
  m.forEach((t, k) => {
    const n = k ? k + 1 : "";
    assert.equal(p.labels[`camera:start${n}`], t.at);
    assert.equal(p.labels[`camera:end${n}`], END(t));
  });
});

test("the overview frames the whole map inside the content box", async () => {
  const p = played(await drawn(canvas()));
  const overview = moves(p).at(-1);
  const s = overview.to.scale;
  assert.ok(s < 1 && s > 0);
  // 3 cards of 720 and 2 gaps of 120 across, centred in the 1680 x 772 box
  assert.ok(Math.abs(overview.to.x - (1680 / 2 - (s * 2400) / 2)) < 0.01);
  assert.ok(2400 * s <= 1680 && 340 * s <= 772);
  // a visit is at full size, centred on the card
  const visit = moves(p)[0];
  assert.equal(visit.to.scale, 1);
  assert.equal(visit.to.x, 1680 / 2 - (720 + 120 + 360));
});

test("an item reads while the camera is on it: the others fall to a level the layout gate skips", async () => {
  const html = await drawn(canvas());
  assert.match(html, /\.cvi \{[^}]*opacity: 0\.3/);
  const p = played(html);
  const fades = p.tweens.filter((t) => /^\.i\d/.test(t.sel) && t.to);
  // item 2 comes up as the camera lands on it, item 1 goes down with it
  const up = fades.find((t) => t.sel === ".i1" && t.to.opacity === 1);
  const down = fades.find((t) => t.sel === ".i0" && t.to.opacity === 0.3);
  assert.equal(END(up), 1.8);
  assert.equal(down.at, up.at);
  // the overview brings every item to full
  const last = moves(p).at(-1);
  for (const i of [0, 1, 2])
    assert.ok(
      fades.some(
        (t) => t.sel === `.i${i}` && t.to.opacity === 1 && t.at === last.at,
      ),
    );
});

test("right to left, the first item sits at the right and the tour runs leftwards", async () => {
  const left = (html, i) =>
    +html.match(
      new RegExp(`class="cvi i${i}"[^>]*style="left: (-?[\\d.]+)px`),
    )[1];
  const ltr = await drawn(canvas(), "ltr");
  const rtl = await drawn(canvas(), "rtl");
  assert.ok(left(ltr, 0) < left(ltr, 1) && left(ltr, 1) < left(ltr, 2));
  assert.ok(left(rtl, 0) > left(rtl, 1) && left(rtl, 1) > left(rtl, 2));
  // the camera's x falls as it moves along the map in Latin, rises in Arabic
  const x = (html) =>
    moves(played(html))
      .slice(0, 2)
      .map((m) => m.to.x);
  assert.ok(x(ltr)[1] < x(ltr)[0]);
  assert.ok(x(rtl)[1] > x(rtl)[0]);
});

test("four to six items take two rows, so the map stays framed at a readable size", async () => {
  const six = Array.from({ length: 6 }, (_, i) => ({
    at: 1,
    title: `T${i}`,
    body: "b",
  }));
  const overview = moves(played(await drawn(canvas(six)))).at(-1);
  // 3 columns x 2 rows: 2400 x 800 at the scale that fits, whose 40 px body
  // text stays over the 24 px floor
  assert.ok(overview.to.scale * 40 >= 24);
  assert.ok(2400 * overview.to.scale <= 1680 && 800 * overview.to.scale <= 772);
});

test("the cards' text is escaped and its Latin runs are isolated in Arabic", async () => {
  const html = await drawn(
    canvas([
      { at: 1, title: "A <b> & C", body: "x" },
      { at: 2, title: "B", body: "y" },
    ]),
  );
  assert.match(html, /A &lt;b&gt; &amp; C/);
  const rtl = await drawn(
    canvas([
      { at: 1, title: "نظام Git", body: "x" },
      { at: 2, title: "ب", body: "y" },
    ]),
    "rtl",
  );
  assert.match(rtl, /<bdi class="lat[^"]*">Git<\/bdi>/);
});

test("a last item cued too near the scene's end for the pull-back to the overview is refused", async () => {
  const late = { ...timing, sentences: [0, 2, 9.4] };
  await assert.rejects(
    drawn(canvas(), "ltr", late),
    /last item lands at 9\.4 s.*pull back to the overview/,
  );
  // 1.1 s is what the pull-back needs: a last cue that leaves it is drawn
  const fits = { ...timing, sentences: [0, 2, 8.9] };
  assert.ok(
    END(moves(played(await drawn(canvas(), "ltr", fits))).at(-1)) <= 10,
  );
});

test("the map's viewport clips at the frame's sides, not the content band's, so a neighbour runs off the frame", async () => {
  const html = await drawn(canvas());
  const rule = html.match(/\.cvp \{([^}]*)\}/)[1];
  // the band's own edge, 120 px in, would cut a card in open space
  assert.doesNotMatch(rule, /overflow: hidden/);
  const side = W - CONTENT.left - CONTENT.width;
  assert.match(
    rule,
    new RegExp(`clip-path: inset\\(0px -${side}px 0px -${CONTENT.left}px\\)`),
  );
});
