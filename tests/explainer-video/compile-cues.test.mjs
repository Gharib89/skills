// The compile stage through its process door, part 2: a visual's cue phrases,
// its emphasis and the props each component takes.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { compiled, fixture, run } from "./compile-lib.mjs";

// One scene of three sentences around `visual`, for the cue and prop tests.
const around = (visual) => `# Cues
language: en
narrator: am_fenrir

## Scene only · The only scene

### Narration
1. It reads the issue. [ex-1]
2. It writes a failing test. [ex-2]
3. Then the code makes it pass. [ex-5]

### Visual
\`\`\`json
${JSON.stringify(visual)}
\`\`\`
`;

const cards = (items, emphasis) => ({
  component: "cards",
  props: { items, ...(emphasis && { emphasis }) },
});
const three = [
  { at: 1, label: "Input", value: "issue" },
  { at: 2, label: "First", value: "test" },
  { at: 3, label: "Then", value: "code" },
];
const withOn = (on) => three.map((x, i) => (i === 1 ? { ...x, on } : x));

test("a cue's `on` phrase compiles when its sentence says it, and the script keeps it", () => {
  const fx = fixture(around(cards(withOn("failing test"))));
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(compiled(fx).scenes[0].visual.props.items[1].on, "failing test");
});

test("a cue's `on` phrase of bare punctuation does not land on a dash the sentence holds", () => {
  const fx = fixture(
    around(cards(withOn("..."))).replace("It writes a", "It writes - a"),
  );
  const r = run(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^compile: only: on "\.\.\." is not said in sentence 2/m);
});

test("a cue's `on` phrase matches whatever its case and punctuation, inside a word as at its edge", () => {
  for (const [phrase, sentence] of [
    ["A FAILING, test!", "It writes a failing test."],
    ["cant fail", "It can't fail the test."],
    ["can't fail", "It cant fail the test."],
  ]) {
    const fx = fixture(
      around(cards(withOn(phrase))).replace(
        "It writes a failing test.",
        sentence,
      ),
    );
    const r = run(fx);
    assert.equal(r.code, 0, `${phrase}: ${r.out}${r.err}`);
  }
});

for (const [name, visual, why] of [
  [
    "an `on` phrase the cue's sentence does not contain",
    cards(withOn("passing test")),
    /^compile: only: on "passing test" is not said in sentence 2/m,
  ],
  [
    "an `on` phrase that is only in another sentence",
    cards(withOn("issue")),
    /^compile: only: on "issue" is not said in sentence 2/m,
  ],
  [
    "an `on` phrase that is only part of a spoken word",
    cards(withOn("fail")),
    /^compile: only: on "fail" is not said in sentence 2/m,
  ],
  [
    "an `on` phrase of bare punctuation",
    cards(withOn("...")),
    /^compile: only: on "\.\.\." is not said in sentence 2/m,
  ],
  [
    "an `on` phrase of only whitespace",
    cards(withOn("  ")),
    /^compile: only: on needs the words of the sentence/m,
  ],
  [
    "an `on` phrase that is not text",
    cards(withOn(7)),
    /^compile: only: on needs the words of the sentence/m,
  ],
  [
    "an `on` phrase on the codediff's own cue",
    {
      component: "codediff",
      props: { lang: "js", before: "a", after: "b", at: 2, on: "tests" },
    },
    /^compile: only: on "tests" is not said in sentence 2/m,
  ],
  [
    "an emphasis that matches no item",
    cards(three, { target: "Nowhere", at: 3 }),
    /^compile: only: cards emphasis target "Nowhere" matches no item/m,
  ],
  [
    "an emphasis that matches two items",
    cards(
      three.map((x) => ({ ...x, label: "Same" })),
      { target: "Same", at: 3 },
    ),
    /^compile: only: cards emphasis target "Same" matches 3 items/m,
  ],
  [
    "an emphasis in a sentence before its item appears",
    cards(three, { target: "Then", at: 2 }),
    /^compile: only: cards emphasis of "Then" lands before the item appears \(at 3\)/m,
  ],
  [
    "an emphasis on a phrase before its item's own phrase",
    cards(withOn("failing test"), { target: "First", at: 2, on: "writes" }),
    /^compile: only: cards emphasis of "First" lands before the item appears \(at 2 on "failing test"\)/m,
  ],
  [
    "an emphasis with no sentence to land at",
    cards(three, { target: "First" }),
    /^compile: only: at undefined is not a sentence \(1 to 3\)/m,
  ],
  [
    "an emphasis on a component with no items to name",
    {
      component: "title",
      props: { title: "x", emphasis: { target: "x", at: 1 } },
    },
    /^compile: only: title has no prop emphasis/m,
  ],
]) {
  test(`compile refuses ${name}, naming the scene`, () => {
    const fx = fixture(around(visual));
    const r = run(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.err, why);
    assert.ok(!fs.existsSync(path.join(fx.dir, "script.json")));
  });
}

test("an emphasis names an item by its text in every component that has items, and a code range by its lines", () => {
  const rows = (key) => three.map((x) => ({ at: x.at, [key]: x.label }));
  for (const visual of [
    cards(three, { target: "First", at: 2, on: "failing" }),
    {
      component: "terminal",
      props: { lines: rows("text"), emphasis: { target: "Then", at: 3 } },
    },
    {
      component: "flow",
      props: { steps: rows("label"), emphasis: { target: "Input", at: 1 } },
    },
    {
      component: "panels",
      props: {
        items: three.map((x) => ({ at: x.at, title: x.label, body: x.value })),
        emphasis: { target: "First", at: 2 },
      },
    },
    {
      component: "list",
      props: { items: rows("text"), emphasis: { target: "Then", at: 3 } },
    },
    {
      component: "code",
      props: {
        lang: "js",
        code: "a\nb",
        emphasis: { target: [2, 2], at: 3, on: "pass" },
      },
    },
  ]) {
    const fx = fixture(around(visual));
    const r = run(fx);
    assert.equal(r.code, 0, `${visual.component}: ${r.out}${r.err}`);
  }
});

// The eight components with the fewest props each takes.
const MINIMAL = {
  title: { title: "x" },
  cards: { items: [{ at: 1, label: "a", value: "b" }] },
  terminal: { lines: [{ at: 1, text: "a" }] },
  flow: {
    steps: [
      { at: 1, label: "a" },
      { at: 2, label: "b" },
    ],
  },
  panels: {
    items: [
      { at: 1, title: "a", body: "b" },
      { at: 2, title: "c", body: "d" },
    ],
  },
  list: { items: [{ at: 1, text: "a" }] },
  code: { lang: "js", code: "a" },
  codediff: { lang: "js", before: "a", after: "b", at: 1 },
};

for (const [component, props] of Object.entries(MINIMAL)) {
  test(`${component} compiles with its own props and refuses an unknown one`, () => {
    assert.equal(run(fixture(around({ component, props }))).code, 0, component);
    const fx = fixture(around({ component, props: { ...props, bogus: 1 } }));
    const r = run(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(
      r.err,
      new RegExp(`^compile: only: ${component} has no prop bogus \\(`, "m"),
    );
  });
}

test("an unknown prop on an item is refused too, naming the item and the props it takes", () => {
  const fx = fixture(
    around(cards([{ at: 1, label: "a", value: "b", notes: "c" }])),
  );
  const r = run(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^compile: only: a cards item has no prop notes \(at, on, label, value, note\)/m,
  );
});
