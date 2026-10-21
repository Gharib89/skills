// The `excerpt` component drawn: the cited excerpt's own words on a document
// surface (a code excerpt on a code one), a source line naming its locator, the
// emphasised sentence lit and the rest dimmed on its cue, and numbered chips
// that pop in on theirs. In Arabic the document reads right to left, one span
// to a whole word; a code excerpt stays left to right.
import { test } from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const PROSE =
  "The cache is cleared on every deploy. Stale entries never survive a release. Readers see fresh data.";
const CODE =
  "const cache = new Map();\nfunction clear() {\n  cache.clear();\n}";
const ARABIC =
  "يمسح النظام الذاكرة المؤقتة عند كل نشر. لا تبقى أي بيانات قديمة.";
const excerpts = {
  "ex-1": { text: PROSE, locator: "§ Caching", code: false },
  "ex-2": { text: CODE, locator: "src/cache.js:3-6", code: true },
  "ex-3": { text: ARABIC, locator: "line 4", code: false },
};
const said = [
  "The cache is wiped on every deploy.",
  "No stale entry survives a release.",
  "The code does it in one call.",
];
const timing = {
  duration: 10,
  slot: 10,
  sentences: [0, 3, 6],
  words: Array.from({ length: 18 }, (_, i) => +(i * 0.5).toFixed(6)),
};
const drawn = (props, dir = "ltr", at = timing, more = {}) =>
  sceneFile(
    {
      id: "a",
      narration: said,
      visual: {
        component: "excerpt",
        props: { excerpts: { ...excerpts, ...more }, ...props },
      },
    },
    at,
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
// The text a block of markup shows, tags dropped and entities read.
const shown = (html) =>
  html
    .replace(/<[^>]*>/g, "")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&amp;", "&");
const block = (html, cls) =>
  html.match(new RegExp(`<div class="${cls}[^"]*"[^>]*>([\\s\\S]*?)</div>`))[1];

test("the document shows the excerpt's own words and nothing else", async () => {
  const html = await drawn({ cite: "ex-1" });
  assert.equal(shown(block(html, "xt")), PROSE);
  // a code excerpt keeps its lines and their indent
  const code = await drawn({ cite: "ex-2" });
  assert.equal(
    [...code.matchAll(/<div class="xs xs\d[^"]*"[^>]*>([\s\S]*?)<\/div>/g)]
      .map((m) => shown(m[1]))
      .join("\n"),
    CODE,
  );
});

test("the source line is the excerpt's locator, in the script it is written in", async () => {
  const html = await drawn({ cite: "ex-2" });
  assert.match(html, /<div class="xsrc" dir="ltr">src\/cache\.js:3-6<\/div>/);
  const ar = await drawn({ cite: "ex-3" }, "rtl");
  assert.match(ar, /<div class="xsrc" dir="ltr">line 4<\/div>/);
  // an Arabic locator reads right to left, its Latin term isolated
  const where = {
    "ex-5": { text: ARABIC, locator: "§ الذاكرة pull", code: false },
  };
  const loc = await drawn({ cite: "ex-5" }, "rtl", timing, where);
  assert.match(
    loc,
    /<div class="xsrc" dir="rtl">§ الذاكرة <bdi class="lat">pull<\/bdi><\/div>/,
  );
});

test("a Latin run stays on one line in an Arabic run, a locator wraps in English", async () => {
  const ar = await drawn(
    { cite: "ex-3", chips: [{ at: 2, cite: "ex-2" }] },
    "rtl",
  );
  assert.match(ar, /\.xw \{[^}]*white-space: nowrap/);
  assert.match(ar, /\.xsrc \{[^}]*white-space: nowrap/);
  assert.match(ar, /\.xl \{[^}]*white-space: nowrap/);
  const en = await drawn({ cite: "ex-1" });
  assert.match(en, /\.xw \{[^}]*white-space: nowrap/);
  assert.match(en, /\.xsrc \{[^}]*overflow-wrap: anywhere/);
  assert.doesNotMatch(en, /\.xsrc \{[^}]*white-space/);
});

test("the emphasised sentence is lit and the rest dimmed on its cue", async () => {
  const html = await drawn({
    cite: "ex-1",
    emphasis: { target: "Stale entries never survive a release.", at: 2 },
  });
  const sentences = [...html.matchAll(/<span class="xs ([^"]*)"/g)].map(
    (m) => m[1],
  );
  assert.deepEqual(
    sentences.map((c) => c.split(" ").at(-1)),
    ["dim", "lit", "dim"],
  );
  const out = tweens(html);
  // the rest fall to the muted colour at sentence 2's start, 3 s in
  const dim = all(".xs.dim", out);
  assert.equal(dim.length, 1);
  assert.equal(dim[0][1].color, claude.colors.text);
  assert.equal(dim[0][2].color, claude.colors.muted);
  assert.equal(dim[0][3], 3);
  // each word of the lit sentence is underlined, on the same cue
  const words = out.filter(([s]) => /^\.lw\d+$/.test(s));
  assert.equal(words.length, 6);
  for (const [, , , t] of words) assert.equal(t, 3);
  assert.equal(words[0][2].backgroundSize, "100% 4px");
});

test("the words of a lit sentence start a step apart, within the light-up window", async () => {
  const lw = (html) =>
    tweens(html)
      .filter(([s]) => /^\.lw\d+$/.test(s))
      .map(([, , to]) => to.delay);
  const target = "Stale entries never survive a release.";
  // 6 words at 0.08 s: the step cap
  assert.deepEqual(
    lw(await drawn({ cite: "ex-1", emphasis: { target, at: 2 } })),
    [0, 0.08, 0.16, 0.24, 0.32, 0.4],
  );
  // 30 words would run 2.4 s at that step: they share 0.6 s instead
  const long = Array.from({ length: 30 }, (_, i) => `w${i}`).join(" ") + ".";
  const delays = lw(
    await drawn(
      { cite: "ex-9", emphasis: { target: long, at: 2 } },
      "ltr",
      timing,
      { "ex-9": { text: long, locator: "x", code: false } },
    ),
  );
  assert.equal(delays.length, 30);
  assert.equal(delays[1], 0.02);
  assert.ok(delays.at(-1) <= 0.6);
  // "in one call" cues on the 18th spoken word, `t` s into a 10 s scene; the
  // cue leaves 10 - t - 0.35 s to start the sentence's 4 words
  const cuedAt = async (t) =>
    lw(
      await drawn(
        {
          cite: "ex-1",
          emphasis: {
            target: "Readers see fresh data.",
            at: 3,
            on: "in one call",
          },
        },
        "ltr",
        { ...timing, words: timing.words.map((w, i) => (i === 17 ? t : w)) },
      ),
    );
  // 0.2 s of room is shared out: a step of 0.05 s
  assert.deepEqual(await cuedAt(9.45), [0, 0.05, 0.1, 0.15]);
  // none left (exactly, then past it): every word at once
  assert.deepEqual(await cuedAt(9.65), [0, 0, 0, 0]);
  assert.deepEqual(await cuedAt(9.7), [0, 0, 0, 0]);
});

test("an emphasis cued on a phrase lights on that phrase's word", async () => {
  const html = await drawn({
    cite: "ex-1",
    emphasis: { target: "Readers see fresh data.", at: 3, on: "in one call" },
  });
  // 13 words come before sentence 3 and "in one call" starts at its 5th: the
  // 18th spoken word, 8.5 s in
  assert.equal(all(".xs.dim", tweens(html))[0][3], 8.5);
});

test("with no emphasis nothing is dimmed or lit", async () => {
  const html = await drawn({ cite: "ex-1" });
  assert.doesNotMatch(html, /class="xs [^"]*(lit|dim)/);
  assert.equal(tweens(html).filter(([s]) => /^\.(xs|lw)/.test(s)).length, 0);
});

test("a code excerpt is lit by line", async () => {
  const html = await drawn({
    cite: "ex-2",
    emphasis: { target: "  cache.clear();", at: 3 },
  });
  const lines = [...html.matchAll(/<div class="xs ([^"]*)"/g)].map((m) =>
    m[1].split(" ").at(-1),
  );
  assert.deepEqual(lines, ["dim", "dim", "lit", "dim"]);
});

test("each chip pops in on its cue, numbered in order with its locator", async () => {
  const html = await drawn({
    cite: "ex-1",
    chips: [
      { at: 2, cite: "ex-2" },
      { at: 3, on: "in one call", cite: "ex-3" },
    ],
  });
  const chips = [...html.matchAll(/<div class="xc xc(\d)">([\s\S]*?)<\/div>/g)];
  assert.deepEqual(
    chips.map((m) => [m[1], shown(m[2])]),
    [
      ["0", "1src/cache.js:3-6"],
      ["1", "2line 4"],
    ],
  );
  const out = tweens(html);
  assert.equal(all(".xc0", out)[0][3], 3);
  assert.equal(all(".xc1", out)[0][3], 8.5);
});

test("an Arabic excerpt reads right to left, one span to a whole word", async () => {
  const html = await drawn({ cite: "ex-3" }, "rtl");
  assert.match(html, /<div class="content" dir="rtl">/);
  const words = [
    ...html.matchAll(/<span class="xw[^"]*">([^<]*)<\/span>/g),
  ].map((m) => m[1]);
  assert.deepEqual(words, ARABIC.split(" "));
  assert.equal(shown(block(html, "xt")), ARABIC);
  // the lit underline starts from the right
  assert.match(html, /\[dir="rtl"\] \.xs\.lit \.xw \{[^}]*100% 100%/);
});

test("a code excerpt stays left to right in an Arabic run", async () => {
  const html = await drawn({ cite: "ex-2" }, "rtl");
  assert.match(html, /<div class="xd xcode" dir="ltr">/);
});

test("the document's direction is the excerpt's own script, not the run's", async () => {
  // an English README quoted in an Arabic run stays left to right, a word to a
  // span and no Latin wrapper that keeps a sentence on one line
  const en = await drawn({ cite: "ex-1" }, "rtl");
  assert.match(en, /<div class="xd" dir="ltr">/);
  assert.deepEqual(
    [...en.matchAll(/<span class="xw[^"]*">([^<]*)<\/span>/g)].map((m) => m[1]),
    PROSE.split(" "),
  );
  assert.doesNotMatch(block(en, "xt"), /<bdi/);
  // and an Arabic excerpt quoted in an English run reads right to left
  const ar = await drawn({ cite: "ex-3" });
  assert.match(ar, /<div class="xd" dir="rtl">/);
  assert.match(ar, /\.xd\[dir="rtl"\] \.xs\.lit \.xw \{[^}]*100% 100%/);
});

test("each sentence is one reading box, a code excerpt's line likewise", async () => {
  const prose = await drawn({ cite: "ex-1" });
  assert.deepEqual(
    [...prose.matchAll(/<span class="xs [^"]*" data-line="(s\d)"/g)].map(
      (m) => m[1],
    ),
    ["s0", "s1", "s2"],
  );
  const code = await drawn({ cite: "ex-2" });
  assert.equal(
    [...code.matchAll(/<div class="xs [^"]*" data-line="s\d"/g)].length,
    4,
  );
});

test("the document draws in the profile's tokens only", async () => {
  const html = await drawn({
    cite: "ex-1",
    chips: [{ at: 2, cite: "ex-2" }],
  });
  const css = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  assert.doesNotMatch(css, /#[0-9a-f]{3,8}\b|rgba?\(/i);
});
