// The visual vocabulary a scene's `### Visual` block names: per component, the
// props it takes (`props`, and `item` for each entry of its `rows` list), what
// they must hold (`check`, throwing the reason) and what it shows a viewer to
// read (`items`, as [name, sentence it rises at, texts], which the camera beat
// reads). The compile stage checks, the video gates time the reading from the
// rendered frames; render/compose.mjs draws each. A cue is lib/props.mjs's.

import { checkBrowser } from "./browser.mjs";
import { checkCanvas } from "./canvas.mjs";
import { checkCustom } from "./custom.mjs";
import { checkDiagram } from "./diagram.mjs";
import { checkExcerpt } from "./excerpt.mjs";
import { digits, numberIn, numbersIn } from "./figures.mjs";
import { shownText } from "./fragment.mjs";
import { checkStack3d } from "./stack3d.mjs";
import {
  CUE,
  cue,
  fail,
  findPhrase,
  known,
  list,
  named,
  object,
  place,
  text,
  words,
} from "./props.mjs";

// A code frame holds this many lines at 30 px: longer code is a second scene.
const CODE_LINES = 12;
export const lines = (code) => code.split("\n");

export { numberIn };

// The techniques a style profile may ban beside the components, each with the
// components that use it: `draw` strokes arrows on, `kinetic` moves type word
// by word, `3d` draws with WebGL. The texture draws `blur`, not a component: the
// profile loader checks it there, and the type family `words` the same way for
// `kinetic`. `camera` is a scene's `camera` key, which compile checks, and the
// `canvas` component, whose camera tours its map.
export const TECHNIQUES = {
  draw: ["flow", "diagram"],
  blur: [],
  camera: ["canvas"],
  kinetic: ["words", "browser"],
  "3d": ["stack3d"],
};

// Whether a scene draws WebGL, which the render and the gates take the GPU
// path for, and whether any of `scenes` does.
export const isWebgl = (s) => !!VISUALS[s.visual.component].webgl;
export const drawsWebgl = (scenes) => scenes.some(isWebgl);

// The index, among the scene's spoken words, of the word the cue `{ at, on }`
// lands on: the sentence's first word, or the phrase's.
export function cueWord(narration, { at, on }) {
  const before = narration
    .slice(0, at - 1)
    .reduce((n, s) => n + words(s).length, 0);
  return on === undefined ? before : before + findPhrase(narration[at - 1], on);
}

// The index, among the scene's spoken words, of the first word of a `words`
// line whose words each land on their own spoken word, or -1: the line's text
// is said in its sentence and its cue lands on that phrase's first word. A line
// cued anywhere else (or whose text the sentence never says) rises as a block
// on its cue.
export function readAlong(narration, { at, on, text }) {
  if (findPhrase(narration[at - 1], text) < 0) return -1;
  const start = cueWord(narration, { at, on: text });
  return cueWord(narration, { at, on }) === start ? start : -1;
}

// The lines of `a` and `b` as keep, del and add rows, the longest common
// subsequence kept: what a code diff draws and what its reader reads.
export function diff(a, b) {
  const L = Array.from({ length: a.length + 1 }, () =>
    new Array(b.length + 1).fill(0),
  );
  for (let i = a.length - 1; i >= 0; i--)
    for (let j = b.length - 1; j >= 0; j--)
      L[i][j] =
        a[i] === b[j]
          ? L[i + 1][j + 1] + 1
          : Math.max(L[i + 1][j], L[i][j + 1]);
  const out = [];
  let i = 0;
  let j = 0;
  while (i < a.length || j < b.length)
    if (i < a.length && j < b.length && a[i] === b[j])
      out.push(["keep", i++, j++]);
    else if (j < b.length && (i === a.length || L[i][j + 1] >= L[i + 1][j]))
      out.push(["add", i, j++]);
    else out.push(["del", i++, j]);
  return out;
}

// The one item `emphasis` names by the `texts` its component shows for each.
function emphasis(name, p, said, texts) {
  const e = p.emphasis;
  if (e === undefined) return;
  object(e, `${name} emphasis`);
  cue(e, said);
  const hits = texts.filter((t) => t === e.target).length;
  if (hits !== 1)
    fail(
      hits
        ? `${name} emphasis target "${e.target}" matches ${hits} items; name one`
        : `${name} emphasis target "${e.target}" matches no item (${texts.join(", ")})`,
    );
  known(`${name} emphasis`, e, EMPHASIS);
  // The callout sits inside its item, so it cannot show before the item does.
  const target = p[VISUALS[name].rows][texts.indexOf(e.target)];
  if (!(place(e, said) >= place(target, said)))
    fail(
      `${name} emphasis of "${e.target}" lands before the item appears (at ${target.at}${target.on ? ` on "${target.on}"` : ""})`,
    );
}
// A code emphasis names a line range, counted from 1.
function codeEmphasis(p, said) {
  const e = p.emphasis;
  if (e === undefined) return;
  object(e, "code emphasis");
  cue(e, said);
  const k = lines(p.code).length;
  const [a, b] = Array.isArray(e.target) ? e.target : [];
  if (!(
    Number.isInteger(a) &&
    Number.isInteger(b) &&
    a >= 1 &&
    a <= b &&
    b <= k
  ))
    fail(
      `code emphasis lines ${a} to ${b} are not lines of the code (1 to ${k})`,
    );
  known("code emphasis", e, EMPHASIS);
}
const EMPHASIS = ["target", ...CUE];
function code(name, v, what) {
  text(name, v, what);
  const k = lines(v).length;
  if (k > CODE_LINES)
    fail(`${name} runs ${k} lines; a frame holds ${CODE_LINES}`);
}

export const VISUALS = {
  title: {
    props: ["kicker", "title", "subtitle"],
    check: (p) => text("title", p.title, "a title"),
    items: (p) => [["title", 1, [p.kicker, p.title, p.subtitle]]],
  },
  cards: {
    props: ["items", "emphasis"],
    rows: "items",
    item: [...CUE, "label", "value", "note"],
    check: (p, said) => {
      list("cards", p.items, "items", said);
      for (const x of p.items) {
        text("cards", x.label, "a label per item");
        text("cards", x.value, "a value per item");
      }
      emphasis(
        "cards",
        p,
        said,
        p.items.map((x) => x.label),
      );
    },
    items: (p) =>
      p.items.map((x, i) => [
        `item ${i + 1}`,
        x.at,
        [x.label, x.value, x.note],
        x.on,
      ]),
  },
  terminal: {
    props: ["title", "lines", "emphasis"],
    rows: "lines",
    item: [...CUE, "text"],
    check: (p, said) => {
      list("terminal", p.lines, "lines", said);
      for (const x of p.lines) text("terminal", x.text, "a text per line");
      emphasis(
        "terminal",
        p,
        said,
        p.lines.map((x) => x.text),
      );
    },
    items: (p) =>
      p.lines.map((x, i) => [`line ${i + 1}`, x.at, [x.text], x.on]),
  },
  flow: {
    props: ["steps", "emphasis"],
    rows: "steps",
    item: [...CUE, "label", "note"],
    check: (p, said) => {
      list("flow", p.steps, "steps", said, [2, 5]);
      for (const x of p.steps) text("flow", x.label, "a label per step");
      emphasis(
        "flow",
        p,
        said,
        p.steps.map((x) => x.label),
      );
    },
    items: (p) =>
      p.steps.map((x, i) => [`step ${i + 1}`, x.at, [x.label, x.note], x.on]),
  },
  panels: {
    props: ["items", "emphasis"],
    rows: "items",
    item: [...CUE, "title", "body"],
    check: (p, said) => {
      list("panels", p.items, "items", said, [2, 3]);
      for (const x of p.items) {
        text("panels", x.title, "a title per item");
        text("panels", x.body, "a body per item");
      }
      emphasis(
        "panels",
        p,
        said,
        p.items.map((x) => x.title),
      );
    },
    items: (p) =>
      p.items.map((x, i) => [`panel ${i + 1}`, x.at, [x.title, x.body], x.on]),
  },
  list: {
    props: ["title", "items", "emphasis"],
    rows: "items",
    item: [...CUE, "text"],
    check: (p, said) => {
      list("list", p.items, "items", said, [1, 6]);
      for (const x of p.items) text("list", x.text, "a text per item");
      emphasis(
        "list",
        p,
        said,
        p.items.map((x) => x.text),
      );
    },
    items: (p) => [
      ...(p.title ? [["title", 1, [p.title]]] : []),
      ...p.items.map((x, i) => [`item ${i + 1}`, x.at, [x.text], x.on]),
    ],
  },
  // Key lines of about six words, each staged word by word. It is rich: the
  // component owns the frame, so the grammar's camera never pushes on it.
  words: {
    props: ["lines"],
    rows: "lines",
    item: [...CUE, "text"],
    ownCamera: true,
    check: (p, said) => {
      list("words", p.lines, "lines", said);
      for (const x of p.lines) text("words", x.text, "a text per line");
    },
    items: (p) =>
      p.lines.map((x, i) => [`line ${i + 1}`, x.at, [x.text], x.on]),
  },
  // Bars or a line over 1 or more numbers that count up as each is said. Rich
  // like `words`; `numbers` are what the script gate holds to a cited excerpt.
  chart: {
    props: ["kind", "unit", "items"],
    rows: "items",
    item: [...CUE, "label", "value"],
    ownCamera: true,
    check: (p, said) => {
      if (!["bar", "line"].includes(p.kind))
        fail("chart needs a kind of bar or line");
      if (p.unit !== undefined) text("chart unit", p.unit, "text");
      list("chart", p.items, "items", said);
      if (p.kind === "line" && p.items.length < 2)
        fail("a line chart needs 2 or more items");
      for (const x of p.items) {
        named("chart", x.label, "a label per item");
        digits("chart", x.value);
      }
    },
    items: (p) =>
      p.items.map((x, i) => [
        `item ${i + 1}`,
        x.at,
        [x.label, x.value, p.unit],
        x.on,
      ]),
    numbers: (p) => p.items.map((x) => x.value),
  },
  // Big numbers that count up, each with its label. Rich like `chart`.
  stat: {
    props: ["items"],
    rows: "items",
    item: [...CUE, "value", "label"],
    ownCamera: true,
    check: (p, said) => {
      list("stat", p.items, "items", said);
      for (const x of p.items) {
        digits("stat", x.value);
        named("stat", x.label, "a label per item");
      }
    },
    items: (p) =>
      p.items.map((x, i) => [`stat ${i + 1}`, x.at, [x.value, x.label], x.on]),
    numbers: (p) => p.items.map((x) => x.value),
  },
  // Events along a line in the order written, the first at the reading start.
  // `when` is display text, shown as written and never parsed. Rich like
  // `words`.
  timeline: {
    props: ["items"],
    rows: "items",
    item: [...CUE, "when", "label", "note"],
    ownCamera: true,
    check: (p, said) => {
      list("timeline", p.items, "items", said);
      for (const x of p.items) {
        named("timeline", x.when, "a when per item");
        named("timeline", x.label, "a label per item");
        if (x.note !== undefined)
          text("timeline", x.note, "a note that is text");
      }
    },
    items: (p) =>
      p.items.map((x, i) => [
        `event ${i + 1}`,
        x.at,
        [x.when, x.label, x.note],
        x.on,
      ]),
    // A number in its text is a claim like a chart's value; a `when` is
    // searched, never parsed.
    numbers: (p) =>
      p.items.flatMap((x) => numbersIn([x.when, x.label, x.note])),
  },
  // Two sides, the first at the reading start, each a title over items; a
  // side's title arrives with its first item, so no item cues before it.
  // Rich like `words`.
  compare: {
    props: ["sides"],
    ownCamera: true,
    check: (p, said) => {
      if (!Array.isArray(p.sides) || p.sides.length !== 2)
        fail("compare needs 2 sides");
      for (const s of p.sides) {
        object(s, "a compare side");
        named("compare", s.title, "a title per side");
        list("compare side", s.items, "items", said);
        for (const x of s.items) named("compare", x.text, "a text per item");
        const j = s.items.findIndex(
          (x) => place(x, said) < place(s.items[0], said),
        );
        if (j > 0)
          fail(
            `compare side "${s.title}" item ${j + 1} cues before item 1, which brings in the side's title`,
          );
        known("a compare side", s, ["title", "items"]);
        for (const x of s.items) known("a compare item", x, [...CUE, "text"]);
      }
    },
    items: (p) =>
      p.sides.flatMap((s, i) => [
        [`side ${i + 1}`, s.items[0].at, [s.title], s.items[0].on],
        ...s.items.map((x, j) => [
          `side ${i + 1} item ${j + 1}`,
          x.at,
          [x.text],
          x.on,
        ]),
      ]),
    numbers: (p) =>
      p.sides.flatMap((s) =>
        numbersIn([s.title, ...s.items.map((x) => x.text)]),
      ),
  },
  // Nodes and the links between them, laid out by the composer: the scene
  // file holds no coordinates. Each node and link rises on its own cue, a link
  // no earlier than both its nodes, and a link's packets flow along it from its
  // cue to the scene's end. Rich like `words`.
  diagram: {
    props: ["nodes", "links"],
    ownCamera: true,
    check: checkDiagram,
    items: (p) =>
      p.nodes.map((n, i) => [`node ${i + 1}`, n.at, [n.label, n.note], n.on]),
    numbers: (p) => p.nodes.flatMap((n) => numbersIn([n.label, n.note])),
  },
  // A generic page (a url, a title, elements) and the actions a cursor plays on
  // it, each on its own cue against an element by id: never a real product's
  // look. The page stands from the scene's start, so only typed text arrives
  // later. Rich like `words`. A number on the page, typed text included, is a
  // claim like a diagram's.
  browser: {
    props: ["url", "title", "elements", "actions"],
    ownCamera: true,
    check: checkBrowser,
    items: (p) => [
      ["page", 1, [p.title, p.url, ...p.elements.map((e) => e.text)]],
      ...p.actions
        .filter((a) => a.act === "type")
        .map((a, i) => [`typed ${i + 1}`, a.at, [a.text], a.on]),
    ],
    numbers: (p) =>
      numbersIn([
        p.url,
        p.title,
        ...p.elements.map((e) => e.text),
        ...p.actions.map((a) => a.text),
      ]),
  },
  // One cited excerpt of the source pack on a page or document surface, its
  // text the pack's own and never the scene file's, and numbered chips for
  // further cited excerpts. Not rich: the camera beat reads what it shows.
  excerpt: {
    props: ["cite", "chips", "emphasis"],
    check: checkExcerpt,
    items: (p) => [
      [
        "excerpt",
        1,
        [p.excerpts?.[p.cite]?.text, p.excerpts?.[p.cite]?.locator],
      ],
      ...(p.chips ?? []).map((c, i) => [
        `chip ${i + 1}`,
        c.at,
        [`${i + 1}`, p.excerpts?.[c.cite]?.locator],
        c.on,
      ]),
    ],
  },
  // Items placed on a map the camera visits in the order written, each on its
  // cue, ending on the overview of the whole map. Rich like `words`: the
  // component moves the frame itself.
  canvas: {
    props: ["items"],
    rows: "items",
    item: [...CUE, "title", "body"],
    ownCamera: true,
    check: checkCanvas,
    items: (p) =>
      p.items.map((x, i) => [`item ${i + 1}`, x.at, [x.title, x.body], x.on]),
    numbers: (p) => p.items.flatMap((x) => numbersIn([x.title, x.body])),
  },
  // Lit layers drawn in 3D with WebGL, each rising on its cue with its label
  // (DOM text over the canvas, so the layout gate judges it). Rich like `words`.
  stack3d: {
    props: ["layers"],
    ownCamera: true,
    webgl: true,
    check: checkStack3d,
    items: (p) =>
      p.layers.map((l, i) => [`layer ${i + 1}`, l.at, [l.label], l.on]),
    numbers: (p) => p.layers.flatMap((l) => numbersIn([l.label])),
  },
  code: {
    props: ["lang", "code", "file", "emphasis"],
    retired: {
      highlights:
        'emphasis replaces it, as { "target": [first, last], "at": n }',
    },
    check: (p, said) => {
      text("code", p.lang, "a lang");
      code("code", p.code, "a code");
      codeEmphasis(p, said);
    },
    items: (p) => [["code", 1, [p.file, ...lines(p.code)]]],
  },
  codediff: {
    props: ["lang", "file", "before", "after", ...CUE],
    check: (p, said) => {
      text("codediff", p.lang, "a lang");
      code("codediff", p.before, "a before");
      code("codediff", p.after, "an after");
      cue(p, said);
    },
    items: (p) => {
      const before = lines(p.before);
      const after = lines(p.after);
      return [
        ["code", 1, [p.file, ...before]],
        [
          "diff",
          p.at,
          diff(before, after)
            .filter(([op]) => op === "add")
            .map(([, , j]) => after[j]),
          p.on,
        ],
      ];
    },
  },
  // The agent's own scene: an HTML fragment beside the scene file that adds to
  // the scene's paused timeline, and the cues it reads by name. Compile lints
  // the fragment and keeps its text as `source`. Rich like `words`, and it shows
  // nothing the camera beat could read.
  custom: {
    props: ["file", "intent", "cues"],
    ownCamera: true,
    check: checkCustom,
    items: () => [],
    numbers: (p) => numbersIn([shownText(p.source ?? "")]),
    shown: (p) => [shownText(p.source ?? "")],
  },
};

// The props a visual must hold and no others, for the scene's sentences in
// spoken form; throws why not. The component's own checks come first, so a
// misspelt required prop is reported as the missing one.
// `ctx` reaches a component that reads beyond the scene file: `read(file)` and
// the run's `language`.
export function checkVisual(visual, said, ctx = {}) {
  object(visual, "visual");
  if (visual.seam !== undefined && typeof visual.seam !== "string")
    fail("seam is not a name like zoom-through, cut-the-curve, travel or cut");
  const v = VISUALS[visual.component];
  if (!v) fail(`unknown component ${visual.component}`);
  if (visual.camera !== undefined) {
    // A component with `ownCamera` set moves the frame itself.
    if (v.ownCamera)
      fail(
        `${visual.component} draws its own camera, so it takes no camera key`,
      );
    object(visual.camera, "camera");
    cue(visual.camera, said);
    known("camera", visual.camera, CUE);
  }
  const props = visual.props ?? {};
  v.check(props, said, ctx);
  known(visual.component, props, v.props, v.retired);
  for (const x of props[v.rows] ?? [])
    known(`a ${visual.component} item`, x, v.item);
}

// The cue the scene's camera pushes in on: its `camera` key, else the cue of
// the item that reveals last, a later word of a sentence after an earlier one.
// `said` holds the scene's sentences in spoken form.
export function cameraCue(visual, said) {
  if (visual.camera) return visual.camera;
  let last;
  for (const [, at, , on] of VISUALS[visual.component].items(
    visual.props ?? {},
  ))
    if (!last || place({ at, on }, said) >= place(last, said))
      last = { at, on };
  return last.on === undefined ? { at: last.at } : last;
}
