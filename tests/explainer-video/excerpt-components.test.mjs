// The `excerpt` component at compile: one cited excerpt of the source pack shown
// as proof, a sentence of it lit by `emphasis`, and numbered chips for further
// cited excerpts. The text is the pack's, never the scene file's; a cite the
// scene's narration does not make, or one the pack lacks, is refused. It is not
// rich, so the grammar's `camera` key is allowed.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  VISUALS,
  checkVisual,
} from "../../skills/explainer-video/scripts/lib/visuals.mjs";
import {
  resolveExcerpts,
  units,
} from "../../skills/explainer-video/scripts/lib/excerpt.mjs";

const PROSE =
  "The cache is cleared on every deploy. Stale entries never survive a release. Readers see fresh data.";
const CODE =
  "const cache = new Map();\nfunction clear() {\n  cache.clear();\n}";
const ARABIC =
  "يمسح النظام الذاكرة المؤقتة عند كل نشر. لا تبقى أي بيانات قديمة.";
const pack = {
  sources: [
    { id: "notes", kind: "md" },
    { id: "app", kind: "repo" },
    { id: "guide", kind: "repo" },
  ],
  excerpts: [
    { id: "ex-1", source: "notes", locator: "§ Caching", text: PROSE },
    { id: "ex-2", source: "app", locator: "src/cache.js:3-6", text: CODE },
    { id: "ex-3", source: "notes", locator: "line 4", text: ARABIC },
    {
      id: "ex-4",
      source: "guide",
      locator: "docs/setup.md:1-2",
      text: "Run it.",
    },
  ],
};
const said = [
  "The cache is wiped on every deploy.",
  "No stale entry survives a release.",
  "The code does it in one call.",
];
const ctx = (extra = {}) => ({
  read: (f) => {
    if (f !== "excerpts.json")
      throw Object.assign(new Error(f), { code: "ENOENT" });
    return JSON.stringify(pack);
  },
  language: "en",
  cites: ["ex-1", "ex-2"],
  ...extra,
});
const excerpt = (props) => ({
  component: "excerpt",
  props: { cite: "ex-1", ...props },
});
const bad = (visual, why, c = ctx()) =>
  assert.throws(() => checkVisual(visual, said, c), why);

test("a cited excerpt compiles with no text of its own", () => {
  assert.doesNotThrow(() => checkVisual(excerpt(), said, ctx()));
  bad(excerpt({ text: PROSE }), /excerpt has no prop text/);
});

test("a pack that parses but is not a pack is refused, naming the file", () => {
  for (const held of [{}, { sources: [] }, { sources: {}, excerpts: [] }, []])
    bad(
      excerpt(),
      /excerpts.json must hold a sources list and an excerpts list/,
      ctx({ read: () => JSON.stringify(held) }),
    );
  // each entry holds what an excerpt scene reads of it
  const entry = { id: "ex-1", source: "notes", locator: "l", text: "T." };
  for (const [held, why] of [
    [{ sources: [null], excerpts: [] }, /excerpts.json source 1 needs an id/],
    [
      { sources: [], excerpts: [{ ...entry, text: undefined }] },
      /excerpts.json excerpt 1 needs text/,
    ],
    [
      { sources: [], excerpts: [{ ...entry, locator: 7 }] },
      /excerpts.json excerpt 1 needs a locator/,
    ],
    [
      { sources: [], excerpts: [{ ...entry, id: "" }] },
      /excerpts.json excerpt 1 needs an id/,
    ],
    [
      { sources: [], excerpts: [{ ...entry, text: "  " }] },
      /excerpts.json excerpt 1 needs text/,
    ],
    // a source the pack lacks would read a code excerpt as prose
    [
      {
        sources: [{ id: "notes", kind: "repo" }],
        excerpts: [{ ...entry, source: undefined }],
      },
      /excerpts.json excerpt 1 needs a source its sources list holds/,
    ],
    [
      {
        sources: [{ id: "notes", kind: "repo" }],
        excerpts: [{ ...entry, source: "nots" }],
      },
      /excerpts.json excerpt 1 needs a source its sources list holds/,
    ],
  ])
    bad(excerpt(), why, ctx({ read: () => JSON.stringify(held) }));
  bad(
    excerpt(),
    /excerpts.json cannot be read: /,
    ctx({ read: () => "not json" }),
  );
});

test("a cite the pack lacks, or the narration does not make, is refused", () => {
  bad(
    excerpt({ cite: "ex-9" }),
    /excerpt cite "ex-9" is not in excerpts.json; cite an id it holds, or run the source stage again/,
  );
  bad(
    excerpt({ cite: "ex-3" }),
    /excerpt cite "ex-3" is not cited by the scene's narration \(ex-1, ex-2\)/,
  );
  bad(excerpt({ cite: undefined }), /excerpt needs a cite/);
});

test("a scene with no pack beside it is refused naming the source stage", () => {
  bad(
    excerpt(),
    /excerpt needs excerpts.json beside the scene file: run the source stage first/,
    ctx({
      read: () => {
        throw Object.assign(new Error("x"), { code: "ENOENT" });
      },
    }),
  );
});

test("an emphasis names one sentence of the excerpt, and no other text", () => {
  const e = (target, more) => ({
    emphasis: { target, at: 2, ...more },
  });
  assert.doesNotThrow(() =>
    checkVisual(
      excerpt(e("Stale entries never survive a release.")),
      said,
      ctx(),
    ),
  );
  bad(
    excerpt(e("Stale entries survive a release.")),
    /excerpt emphasis target "Stale entries survive a release." is no sentence of ex-1/,
  );
  // a clause is not a sentence
  bad(excerpt(e("Stale entries never survive")), /is no sentence of ex-1/);
  bad(
    excerpt({ emphasis: { target: "Readers see fresh data." } }),
    /at undefined is not a sentence/,
  );
  bad(
    excerpt(e("Readers see fresh data.", { by: 1 })),
    /excerpt emphasis has no prop by/,
  );
});

test("a sentence the excerpt says twice cannot be named", () => {
  const twice = { ...pack.excerpts[0], text: "Same. Same. Other." };
  bad(
    excerpt({ emphasis: { target: "Same.", at: 1 } }),
    /excerpt emphasis target "Same." matches 2 sentences of ex-1; name one/,
    ctx({
      read: () => JSON.stringify({ ...pack, excerpts: [twice] }),
    }),
  );
});

test("a code excerpt is lit by line, an Arabic one by its sentences", () => {
  assert.doesNotThrow(() =>
    checkVisual(
      excerpt({
        cite: "ex-2",
        emphasis: { target: "  cache.clear();", at: 3 },
      }),
      said,
      ctx(),
    ),
  );
  bad(
    excerpt({ cite: "ex-2", emphasis: { target: "cache.clear();", at: 3 } }),
    /is no line of ex-2/,
  );
  assert.doesNotThrow(() =>
    checkVisual(
      excerpt({
        cite: "ex-3",
        emphasis: { target: "لا تبقى أي بيانات قديمة.", at: 2 },
      }),
      said,
      ctx({ cites: ["ex-3"], language: "ar" }),
    ),
  );
});

test("a chip names an excerpt the scene cites, each on a cue in order", () => {
  const chips = [
    { at: 2, cite: "ex-2" },
    { at: 3, on: "in one call", cite: "ex-3" },
  ];
  const three = ctx({ cites: ["ex-1", "ex-2", "ex-3"] });
  assert.doesNotThrow(() => checkVisual(excerpt({ chips }), said, three));
  // a chip is a further excerpt: not the one shown, and none twice
  bad(
    excerpt({ chips: [{ at: 2, cite: "ex-1" }] }),
    /excerpt chip 1 cites ex-1, the excerpt shown; a chip is a further excerpt/,
  );
  bad(
    excerpt({
      chips: [
        { at: 2, cite: "ex-2" },
        { at: 3, cite: "ex-2" },
      ],
    }),
    /excerpt chip 2 cites ex-2 again; each chip names a different excerpt/,
  );
  bad(
    excerpt({ chips: [{ at: 2, cite: "ex-9" }] }),
    /excerpt chip cite "ex-9" is not in excerpts.json/,
  );
  bad(
    excerpt({ chips: [{ at: 2, cite: "ex-4" }] }),
    /excerpt chip cite "ex-4" is not cited by the scene's narration \(ex-1, ex-2\)/,
  );
  bad(excerpt({ chips: [{ at: 2 }] }), /excerpt chip needs a cite/);
  bad(
    excerpt({ chips: [chips[1], chips[0]] }),
    /excerpt chip 2 cues before chip 1/,
    three,
  );
  bad(
    excerpt({ chips: [{ at: 4, cite: "ex-2" }] }),
    /at 4 is not a sentence \(1 to 3\)/,
  );
  bad(
    excerpt({ chips: [{ at: 2, cite: "ex-2", label: "x" }] }),
    /an excerpt chip has no prop label/,
  );
});

test("the excerpts a scene shows resolve from the pack, locator and kind with each", () => {
  const got = resolveExcerpts(
    {
      cite: "ex-1",
      chips: [
        { at: 2, cite: "ex-2" },
        { at: 3, cite: "ex-4" },
      ],
    },
    ctx().read,
  );
  assert.deepEqual(got, {
    "ex-1": { text: PROSE, locator: "§ Caching", code: false },
    "ex-2": { text: CODE, locator: "src/cache.js:3-6", code: true },
    // a repo source's Markdown file is prose
    "ex-4": { text: "Run it.", locator: "docs/setup.md:1-2", code: false },
  });
});

test("an excerpt splits into sentences, a code one into lines", () => {
  assert.deepEqual(units(PROSE, false), [
    "The cache is cleared on every deploy.",
    "Stale entries never survive a release.",
    "Readers see fresh data.",
  ]);
  assert.deepEqual(units(CODE, true), CODE.split("\n"));
  assert.equal(units(ARABIC, false).length, 2);
});

test("excerpt is registered with items the camera beat can read", () => {
  const { items } = VISUALS.excerpt;
  const props = {
    cite: "ex-1",
    chips: [{ at: 2, cite: "ex-2" }],
    excerpts: {
      "ex-1": { text: PROSE, locator: "§ Caching", code: false },
      "ex-2": { text: CODE, locator: "src/cache.js:3-6", code: true },
    },
  };
  assert.equal(VISUALS.excerpt.ownCamera, undefined);
  assert.deepEqual(
    items(props).map(([name, at]) => [name, at]),
    [
      ["excerpt", 1],
      ["chip 1", 2],
    ],
  );
});
