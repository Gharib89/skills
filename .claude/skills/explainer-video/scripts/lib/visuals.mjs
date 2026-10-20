// The visual vocabulary a scene's `### Visual` block names: per component, the
// props it takes (`props`, and `item` for each entry of its `rows` list), what
// they must hold (`check`, throwing the reason) and what it shows a viewer to
// read (`items`, as [name, sentence it rises at, texts], which the camera beat
// reads). The compile stage checks, the video gates time the reading from the
// rendered frames; render/compose.mjs draws each.
//
// A cue is `at`, a sentence number, and optionally `on`, a phrase that
// sentence says: the reveal lands on the phrase's first spoken word.

import { plain } from "./count.mjs";

// A code frame holds this many lines at 30 px: longer code is a second scene.
const CODE_LINES = 12;
export const lines = (code) => code.split("\n");

// The techniques a style profile may ban beside the components, each with the
// components that use it: `draw` strokes arrows on, `kinetic` moves type word
// by word. The texture draws `blur`, not a component: the profile loader checks
// it there, and the type family `words` the same way for `kinetic`. `camera` is
// a scene's `camera` key, which compile checks.
export const TECHNIQUES = {
  draw: ["flow"],
  blur: [],
  camera: [],
  kinetic: ["words"],
};

const words = (s) => s.split(/\s+/).filter(Boolean);
// A word compared without its case or its punctuation, an apostrophe inside
// it included.
const bare = (w) => w.toLowerCase().replace(/[^\p{L}\p{N}\p{M}]+/gu, "");

// Where in the spoken `sentence` the words of `phrase` first run, as a word
// index, or -1.
export function findPhrase(sentence, phrase) {
  const have = words(sentence).map(bare);
  const want = words(phrase).map(bare);
  // A word of bare punctuation would match a bare dash in the sentence.
  if (want.includes("")) return -1;
  for (let i = 0; i + want.length <= have.length; i++)
    if (want.every((w, j) => w === have[i + j])) return i;
  return -1;
}

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

const fail = (why) => {
  throw new Error(why);
};
const object = (x, what) => {
  if (x === null || typeof x !== "object" || Array.isArray(x))
    fail(`${what} is not a JSON object`);
};
const text = (name, v, what) => {
  if (typeof v !== "string") fail(`${name} needs ${what}`);
};
const named = (name, v, what) => {
  text(name, v, what);
  if (!v.trim()) fail(`${name} needs ${what}`);
};
// A number as a source writes it: digits, thousands commas that group by
// three, an optional decimal part. Its characters are what the script gate
// finds in an excerpt, and what a count-up ends on.
// It is written in ASCII, Arabic-Indic (١٢٠٠) or Persian (۱۲۰۰) digits, one
// script to a number, as an Arabic source writes it.
const NUMBER = /^(0|[1-9]\d*|[1-9]\d{0,2}(,\d{3})+)(\.\d+)?$/;
const SCRIPTS = [/[0-9]/, /[٠-٩]/, /[۰-۹]/];
function digits(name, v) {
  if (v === undefined) fail(`${name} needs a value per item`);
  if (
    typeof v !== "string" ||
    !NUMBER.test(plain(v)) ||
    SCRIPTS.filter((s) => s.test(v)).length > 1
  )
    fail(
      `${name} value ${JSON.stringify(v)} is not a number written in digits (1200 or 1,200.5)`,
    );
  // What a double keeps exactly: a longer one would count up and size a bar
  // from a rounded (or infinite) number.
  if (plain(v).replace(/\D/g, "").length > 15)
    fail(`${name} value ${JSON.stringify(v)} has more than 15 digits`);
}
const DIGIT = "[0-9\\u0660-\\u0669\\u06f0-\\u06f9]";
const POINT = "[.,\\u066b\\u066c]";
// Whether `value` stands in `text` as written and whole, never as part of a
// longer number (200 is not in 1,200 nor 5 in 0.5), in any digit script.
export const numberIn = (text, value) =>
  new RegExp(
    `(?<!${DIGIT})(?<!${DIGIT}${POINT})${value.replace(/\./g, "\\.")}(?!${DIGIT})(?!${POINT}${DIGIT})`,
  ).test(text);
// Every number written in `texts` as `numberIn` reads one: digits joined by a
// point or comma between digits, so `Q3 '21` holds 3 and 21.
const numbersIn = (texts) =>
  texts.flatMap(
    (t) => t?.match(new RegExp(`${DIGIT}+(?:${POINT}${DIGIT}+)*`, "g")) ?? [],
  );
// A list prop of `min` to `max` objects, each with a cue.
function list(name, v, what, said, [min, max] = [1, Infinity]) {
  if (!Array.isArray(v) || v.length < min || v.length > max)
    fail(
      max === Infinity
        ? `${name} needs ${what}`
        : `${name} needs ${min} to ${max} ${what}`,
    );
  for (const x of v) {
    object(x, `a ${name} ${what.replace(/s$/, "")}`);
    cue(x, said);
  }
}
function at(x, n) {
  if (!Number.isInteger(x) || x < 1 || x > n)
    fail(`at ${x} is not a sentence (1 to ${n})`);
}
// `said` holds the scene's sentences in spoken form.
function cue(x, said) {
  at(x.at, said.length);
  if (x.on === undefined) return;
  if (typeof x.on !== "string" || !words(x.on).length)
    fail("on needs the words of the sentence");
  if (findPhrase(said[x.at - 1], x.on) < 0)
    fail(`on "${x.on}" is not said in sentence ${x.at}`);
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
// Where a cue falls in the scene's speech, as a number that orders cues:
// its sentence, then the phrase's word within it.
const place = (x, said) =>
  x.at * 1000 + (x.on === undefined ? 0 : findPhrase(said[x.at - 1], x.on));
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
const CUE = ["at", "on"];
const EMPHASIS = ["target", ...CUE];
// A prop the component does not take is refused, never silently dropped;
// `retired` names where one it once took went.
function known(what, x, allowed, retired = {}) {
  for (const k of Object.keys(x))
    if (!allowed.includes(k))
      fail(
        retired[k]
          ? `${what} has no prop ${k}: ${retired[k]}`
          : `${what} has no prop ${k} (${allowed.join(", ")})`,
      );
}
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
};

// The props a visual must hold and no others, for the scene's sentences in
// spoken form; throws why not. The component's own checks come first, so a
// misspelt required prop is reported as the missing one.
export function checkVisual(visual, said) {
  object(visual, "visual");
  if (visual.seam !== undefined && typeof visual.seam !== "string")
    fail("seam is not a name like zoom-through, cut-the-curve or cut");
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
  v.check(props, said);
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
