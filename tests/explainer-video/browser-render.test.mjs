// The `browser` component drawn: a generic page whose cursor, click and typed
// text play on each action's cue, on the scene's paused timeline. Typed text
// appears a whole word at a time, in Arabic too. Right to left, the page mirrors
// and its URL stays left to right. The page draws in the profile's tokens only.
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { pageLayout } from "../../skills/explainer-video/scripts/render/browser.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const said = [
  "Open the sign-up page.",
  "Type the name into the field.",
  "Then press the button.",
];
const timing = {
  duration: 10,
  slot: 10,
  sentences: [0, 3, 6],
  words: Array.from({ length: 15 }, (_, i) => +(i * 0.6).toFixed(6)),
};
const page = {
  url: "example.com/signup",
  title: "Sign up",
  elements: [
    { id: "head", kind: "heading", text: "Create an account" },
    { id: "name", kind: "field", text: "Your name" },
    { id: "go", kind: "button", text: "Continue" },
  ],
  actions: [
    { at: 1, target: "head", act: "move" },
    { at: 2, target: "name", act: "type", text: "Ada Lovelace" },
    { at: 3, on: "the button", target: "go", act: "click" },
  ],
};
const drawn = (dir = "ltr", props = page, narration = said) =>
  sceneFile(
    { id: "a", narration, visual: { component: "browser", props } },
    timing,
    claude,
    { backend: {}, seam: {}, dir },
  );
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
const all = (sel, list) => list.filter(([s]) => s === sel);

test("the cursor moves to each action's target on its cue, from where the last one left it", async () => {
  const moves = all(".cur", tweens(await drawn()));
  // sentence 3 cued on "the button": the 11th and 12th spoken words, so the
  // phrase starts at the 13th, 7.2 s in
  assert.deepEqual(
    moves.map(([, , , t]) => t),
    [0, 3, 7.2],
  );
  // each move ends at its target's centre (the cursor starts at 1220, 600)
  const boxes = pageLayout(page.elements, false);
  page.actions.forEach((a, i) => {
    const { left, top, w, h } =
      boxes[page.elements.findIndex((e) => e.id === a.target)];
    assert.deepEqual(
      [moves[i][2].x, moves[i][2].y],
      [+(left + w / 2 - 1220).toFixed(2), +(top + h / 2 - 600).toFixed(2)],
    );
  });
  // each move starts where the one before ended
  for (let i = 1; i < moves.length; i++) {
    assert.equal(moves[i][1].x, moves[i - 1][2].x);
    assert.equal(moves[i][1].y, moves[i - 1][2].y);
  }
  // it is moved by the timeline alone, and a later move never repaints the
  // from state of an earlier one
  for (const [, , to] of moves) assert.equal(to.immediateRender, false);
  assert.doesNotMatch(
    await drawn(),
    /Date\.now|performance\.now|requestAnimationFrame|setInterval|animation:|transition:/,
  );
});

test("a move ends when the next action's cue arrives, so the cursor never jumps", async () => {
  // "the" is the scene's 2nd spoken word, 0.6 s in: closer than a full move
  const props = {
    ...page,
    actions: [
      { at: 1, target: "head", act: "move" },
      { at: 1, on: "the", target: "go", act: "click" },
    ],
  };
  const list = tweens(await drawn("ltr", props));
  const moves = all(".cur", list);
  assert.deepEqual(
    moves.map(([, , , t]) => t),
    [0, 0.6],
  );
  assert.equal(moves[0][2].duration, 0.6);
  assert.equal(moves[1][2].duration, 0.7);
  // the click rings once its own, full-length move has arrived
  assert.equal(all(".rp1", list)[0][2].delay, 0.7);
});

test("typed words land before the next action's cue and before the scene ends", async () => {
  const long = Array.from({ length: 20 }, (_, i) => `w${i}`).join(" ");
  const landed = (list) =>
    list
      .filter(([s]) => /^\.tw\d+$/.test(s))
      .map(([, , to, t]) => t + to.delay + to.duration);
  // 20 words at the default step would end 5.45 s + 0.2 s after the cue
  const before = tweens(
    await drawn("ltr", {
      ...page,
      actions: [
        { at: 2, target: "name", act: "type", text: long },
        { at: 3, target: "go", act: "click" },
      ],
    }),
  );
  assert.ok(Math.max(...landed(before)) <= 6, "by the click's cue, 6 s");
  const last = tweens(
    await drawn("ltr", {
      ...page,
      actions: [{ at: 3, target: "name", act: "type", text: long }],
    }),
  );
  assert.ok(Math.max(...landed(last)) <= 10, "by the scene's end, 10 s");
});

test("with no room before the next cue, the typed words still appear whole, together", async () => {
  // the click cues 0.6 s after the type, inside its move and one fade
  const list = tweens(
    await drawn("ltr", {
      ...page,
      actions: [
        { at: 1, target: "name", act: "type", text: "Ada Lovelace" },
        { at: 1, on: "the", target: "go", act: "click" },
      ],
    }),
  );
  const words = list.filter(([s]) => /^\.tw\d+$/.test(s));
  assert.equal(words.length, 2);
  // both land as the cursor arrives, 0.6 s after the cue (the move shortened to
  // the click's cue)
  assert.deepEqual([words[0][2].delay, words[1][2].delay], [0.6, 0.6]);
});

test("a click ripples at its target once the cursor has arrived, and a move ripples nowhere", async () => {
  const html = await drawn();
  const list = tweens(html);
  const ripples = list.filter(([s]) => /^\.rp\d+$/.test(s));
  const go = pageLayout(page.elements, false)[2];
  assert.ok(
    html.includes(
      `class="rp rp2" style="left: ${go.left + go.w / 2}px; top: ${go.top + go.h / 2}px;"`,
    ),
  );
  assert.equal(ripples.length, 1);
  const [sel, from, to, t] = ripples[0];
  assert.equal(sel, ".rp2");
  assert.equal(t, 7.2);
  assert.ok(to.delay > 0, "after the cursor's own move");
  assert.ok(from.opacity > 0 && to.opacity === 0);
});

test("typed text appears a whole word at a time, each after the last, once the cursor has arrived", async () => {
  const html = await drawn();
  const words = tweens(html).filter(([s]) => /^\.tw\d+$/.test(s));
  assert.equal(words.length, 2);
  assert.deepEqual(
    words.map(([, , , t]) => t),
    [3, 3],
  );
  const [a, b] = words.map(([, , to]) => to.delay);
  assert.ok(a > 0 && b > a);
  assert.match(html, /class="tw tw0">Ada<\/span>/);
  assert.match(html, /class="tw tw1">Lovelace<\/span>/);
  // the field's own label gives way to what is typed
  assert.ok(all(".ph1", tweens(html)).length === 1);
});

test("Arabic typed text is whole words, never letters, and a Latin term stays one word", async () => {
  const props = {
    ...page,
    actions: [
      { at: 2, target: "name", act: "type", text: "اكتب طلب pull request هنا" },
    ],
  };
  const html = await drawn("rtl", props);
  const words = [...html.matchAll(/class="tw tw\d+">(.*?)<\/span>/g)].map(
    (m) => m[1],
  );
  assert.deepEqual(words, [
    "اكتب",
    "طلب",
    '<bdi class="lat">pull request</bdi>',
    "هنا",
  ]);
  // the layout gate holds a Latin run in right to left text to one line, and
  // the word's own box is such a run (real-render's layout row found it wrapping)
  assert.match(html, /\.tw \{[^}]*white-space: nowrap/);
});

test("right to left, the page mirrors and the URL stays left to right", async () => {
  const rtl = await drawn("rtl");
  const ltr = await drawn("ltr");
  assert.match(rtl, /<div class="content" dir="rtl">/);
  assert.match(rtl, /<div class="url" dir="ltr">example\.com\/signup<\/div>/);
  // an element stands at the reading start: the left edge in English, the
  // right in Arabic
  const left = (html) =>
    +html.match(/class="el e0[^"]*" style="left: (\d+)px/)[1];
  assert.ok(left(ltr) < left(rtl));
  // and the cursor comes in from the reading end
  const start = (html) => +html.match(/\.cur \{[^}]*left: (\d+)px/)[1];
  assert.ok(start(ltr) > start(rtl));
  const target = (html, i) => all(".cur", tweens(html))[i][2].x;
  assert.ok(target(ltr, 0) < target(rtl, 0));
});

test("the page carries no logo and no colour outside the profile's tokens", async () => {
  const html = await drawn();
  const style = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  assert.doesNotMatch(style, /#[0-9a-f]{3,8}\b|\brgba?\(|\bhsla?\(|\burl\(/i);
  assert.doesNotMatch(html, /<img|<image|<svg[^>]*xlink/);
  // every colour it names is a token
  for (const [, v] of style.matchAll(
    /(?:color|background|border(?!-radius)[\w-]*|fill|stroke):\s*([^;]+);/g,
  ))
    assert.match(v, /var\(--\w+\)|none|transparent|currentColor/);
});
