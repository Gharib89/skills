// The type family `words`: a title and its subtitle compose one masked span per
// whole word, rising in order on their cue (Arabic by whole words, never
// letters), the `block` family keeps today's entrance, and the `kinetic` ban
// holds the grammar and a scene to no per-word motion.
import { test } from "node:test";
import assert from "node:assert/strict";
import { banReason } from "../../skills/explainer-video/scripts/lib/allowed.mjs";
import {
  grammar,
  validate,
} from "../../skills/explainer-video/scripts/lib/style.mjs";
import { sceneFile } from "../../skills/explainer-video/scripts/render/compose.mjs";
import { read, skill } from "./render-lib.mjs";

const claude = JSON.parse(read(skill, "styles", "claude-code.json"));
const odd = (g) => ({ ...claude, name: "odd", grammar: g });

const said = ["Ship takes one issue.", "It opens a pull request."];
const title = {
  component: "title",
  props: { kicker: "Ship", title: "One issue to a request", subtitle: "A run" },
};
const timing = {
  duration: 6,
  slot: 6,
  sentences: [1, 3],
  words: Array.from({ length: 10 }, (_, i) => i * 0.5),
};
const drawn = (visual, profile = claude, narration = said, dir = "ltr") =>
  sceneFile({ id: "a", narration, visual }, timing, profile, {
    backend: {},
    dir,
    seam: {},
  });
// [selector, from, to, position] of each tween on a word.
const rises = (html) =>
  [...html.matchAll(/const tweens = (\[.*\]);/g)].flatMap((m) =>
    JSON.parse(m[1]).filter(([sel]) => /\.k\d+$/.test(sel)),
  );
const spans = (html) => [
  ...html.matchAll(
    /<span class="w"><span class="wi k\d+">(.*?)<\/span><\/span>/g,
  ),
];

test("a profile with no type field plays words, staggering 0.05 s, and the knob is bounded", () => {
  assert.deepEqual(grammar(claude).type, { family: "words", stagger: 0.05 });
  assert.equal(grammar(odd({ type: { stagger: 0.08 } })).type.stagger, 0.08);
  assert.equal(grammar(odd({ type: "block" })).type.family, "block");
  assert.throws(
    () => validate(odd({ type: { stagger: 0.2 } })),
    /grammar\.type\.stagger 0\.2 is outside 0\.03 to 0\.08/,
  );
  assert.throws(
    () => validate(odd({ type: "spin" })),
    /grammar\.type spin is not words or block/,
  );
});

test("a title and a subtitle compose one span per word, revealed in order on their cue", async () => {
  const html = await drawn(title);
  const words = spans(html).map((m) => m[1].replace(/<[^>]*>/g, ""));
  assert.deepEqual(words, ["One", "issue", "to", "a", "request", "A", "run"]);
  const tw = rises(html);
  assert.equal(tw.length, 7);
  // each rises out of its mask under power4.out, on the cue's second, 0.05 s
  // after the word before it
  tw.forEach(([sel, from, to, at], n) => {
    assert.equal(sel, `.k${n}`);
    assert.equal(from.yPercent, 115);
    assert.deepEqual(
      [to.yPercent, to.ease, to.delay, at],
      [0, "power4.out", +(n * 0.05).toFixed(6), 1],
    );
  });
  // the title resolves out of blur, the subtitle does not
  assert.ok(
    tw.slice(0, 5).every(([, f, t]) => f.filter && t.filter === "blur(0px)"),
  );
  assert.ok(tw.slice(5).every(([, f]) => !f.filter));
  assert.match(html, /<div class="kick r0">/);
});

test("the stagger knob spaces the words", async () => {
  const tw = rises(await drawn(title, odd({ type: { stagger: 0.08 } })));
  assert.equal(tw[2][2].delay, 0.16);
});

test("an Arabic run composes one span per whole word and none inside a word", async () => {
  const ar = ["السفينة بتاخد issue وتفتح pull request."];
  const html = await drawn(
    {
      component: "title",
      props: { title: "من issue لحد pull request كامل" },
    },
    claude,
    ar,
    "rtl",
  );
  const words = spans(html);
  // the English term is one unit, kept whole in its isolate
  assert.deepEqual(
    words.map((m) => m[1].replace(/<[^>]*>/g, "")),
    ["من", "issue", "لحد", "pull request", "كامل"],
  );
  assert.match(html, /<bdi class="lat ti">pull request<\/bdi>/);
  for (const m of words) assert.doesNotMatch(m[1], /<span/);
  assert.equal(rises(html).length, 5);
});

test("Arabic letters glued to an English term stay in its word", async () => {
  const html = await drawn(
    { component: "title", props: { title: "وpull request كامل" } },
    claude,
    ["x"],
    "rtl",
  );
  assert.deepEqual(
    spans(html).map((m) => m[1].replace(/<[^>]*>/g, "")),
    ["وpull request", "كامل"],
  );
});

test("a profile with type block composes today's block entrance", async () => {
  const html = await drawn(title, odd({ type: "block" }));
  assert.equal(rises(html).length, 0);
  assert.doesNotMatch(html, /class="w"/);
  // the block entrance: the whole title and subtitle rise at the cue
  assert.match(html, /\["\.r0",\{"opacity":0,"y":\d+\},\{[^}]*"duration":0\.6/);
  assert.match(html, /<div class="big r0">One issue to a request<\/div>/);
});

test("a profile banning kinetic composes no per-word motion, and refuses what needs it", async () => {
  const banned = odd({ bans: ["kinetic"] });
  assert.equal(grammar(banned).type.family, "block");
  assert.equal(rises(await drawn(title, banned)).length, 0);
  assert.throws(
    () => validate(odd({ bans: ["kinetic"], type: "words" })),
    /grammar\.type words moves per word, which grammar\.bans bans/,
  );
  assert.doesNotThrow(() =>
    validate(odd({ bans: ["kinetic"], type: "block" })),
  );
  assert.equal(
    banReason(["kinetic"], "words", "odd"),
    "component words uses kinetic, which style profile odd bans",
  );
  assert.equal(banReason(["kinetic"], "title", "odd"), null);
});

test("a blur ban takes the blur out of the title's rise and leaves the rise", async () => {
  const tw = rises(
    await drawn(
      title,
      odd({
        bans: ["blur"],
        texture: { surface: "flat", overlays: ["vignette"] },
        seams: "cut",
      }),
    ),
  );
  assert.equal(tw.length, 7);
  assert.ok(tw.every(([, f]) => !f.filter));
});
