// The visual vocabulary a scene's `### Visual` block names: per component, the
// props it takes (`props`, and `item` for each entry of its `rows` list), what
// they must hold (`check`, throwing the reason) and what it shows a viewer to
// read (`items`, as [name, sentence it rises at, texts]). The compile stage
// checks, the script gates time the reading; render/compose.mjs draws each.
//
// A cue is `at`, a sentence number, and optionally `on`, a phrase that
// sentence says: the reveal lands on the phrase's first spoken word.

// A code frame holds this many lines at 30 px: longer code is a second scene.
const CODE_LINES = 12;
export const lines = (code) => code.split("\n");

// The techniques a style profile may ban beside the components, each with the
// components that use it: `draw` strokes arrows on.
export const TECHNIQUES = { draw: ["flow"] };

const words = (s) => s.split(/\s+/).filter(Boolean);
// A word compared without its case or the punctuation round it.
const bare = (w) =>
  w.toLowerCase().replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "");

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
    items: (p) => p.lines.map((x, i) => [`line ${i + 1}`, x.at, [x.text]]),
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
      p.steps.map((x, i) => [`step ${i + 1}`, x.at, [x.label, x.note]]),
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
      p.items.map((x, i) => [`panel ${i + 1}`, x.at, [x.title, x.body]]),
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
      ...p.items.map((x, i) => [`item ${i + 1}`, x.at, [x.text]]),
    ],
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
  const v = VISUALS[visual.component];
  if (!v) fail(`unknown component ${visual.component}`);
  const props = visual.props ?? {};
  v.check(props, said);
  known(visual.component, props, v.props, v.retired);
  for (const x of props[v.rows] ?? [])
    known(`a ${visual.component} item`, x, v.item);
}
