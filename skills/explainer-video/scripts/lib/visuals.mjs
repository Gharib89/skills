// The visual vocabulary a scene's `### Visual` block names: per component, what
// its props must hold (`check`, throwing the reason) and what it shows a viewer
// to read (`items`, as [name, sentence it rises at, texts]). The compile stage
// checks, the script gates time the reading; render/compose.mjs draws each.

// A code frame holds this many lines at 30 px: longer code is a second scene.
const CODE_LINES = 12;
export const lines = (code) => code.split("\n");

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
// A list prop of `min` to `max` objects, each with an `at`.
function list(name, v, what, n, [min, max] = [1, Infinity]) {
  if (!Array.isArray(v) || v.length < min || v.length > max)
    fail(
      max === Infinity
        ? `${name} needs ${what}`
        : `${name} needs ${min} to ${max} ${what}`,
    );
  for (const x of v) {
    object(x, `a ${name} ${what.replace(/s$/, "")}`);
    at(x.at, n);
  }
}
function at(x, n) {
  if (!Number.isInteger(x) || x < 1 || x > n)
    fail(`at ${x} is not a sentence (1 to ${n})`);
}
function code(name, v, what) {
  text(name, v, what);
  const k = lines(v).length;
  if (k > CODE_LINES)
    fail(`${name} runs ${k} lines; a frame holds ${CODE_LINES}`);
}

export const VISUALS = {
  title: {
    check: (p) => text("title", p.title, "a title"),
    items: (p) => [["title", 1, [p.kicker, p.title, p.subtitle]]],
  },
  cards: {
    check: (p, n) => {
      list("cards", p.items, "items", n);
      for (const x of p.items) {
        text("cards", x.label, "a label per item");
        text("cards", x.value, "a value per item");
      }
    },
    items: (p) =>
      p.items.map((x, i) => [
        `item ${i + 1}`,
        x.at,
        [x.label, x.value, x.note],
      ]),
  },
  terminal: {
    check: (p, n) => {
      list("terminal", p.lines, "lines", n);
      for (const x of p.lines) text("terminal", x.text, "a text per line");
    },
    items: (p) => p.lines.map((x, i) => [`line ${i + 1}`, x.at, [x.text]]),
  },
  flow: {
    check: (p, n) => {
      list("flow", p.steps, "steps", n, [2, 5]);
      for (const x of p.steps) text("flow", x.label, "a label per step");
    },
    items: (p) =>
      p.steps.map((x, i) => [`step ${i + 1}`, x.at, [x.label, x.note]]),
  },
  panels: {
    check: (p, n) => {
      list("panels", p.items, "items", n, [2, 3]);
      for (const x of p.items) {
        text("panels", x.title, "a title per item");
        text("panels", x.body, "a body per item");
      }
    },
    items: (p) =>
      p.items.map((x, i) => [`panel ${i + 1}`, x.at, [x.title, x.body]]),
  },
  list: {
    check: (p, n) => {
      list("list", p.items, "items", n, [1, 6]);
      for (const x of p.items) text("list", x.text, "a text per item");
    },
    items: (p) => [
      ...(p.title ? [["title", 1, [p.title]]] : []),
      ...p.items.map((x, i) => [`item ${i + 1}`, x.at, [x.text]]),
    ],
  },
  code: {
    check: (p, n) => {
      text("code", p.lang, "a lang");
      code("code", p.code, "a code");
      const k = lines(p.code).length;
      for (const h of p.highlights ?? []) {
        object(h, "a code highlight");
        at(h.at, n);
        const [a, b] = Array.isArray(h.lines) ? h.lines : [];
        if (!(
          Number.isInteger(a) &&
          Number.isInteger(b) &&
          a >= 1 &&
          a <= b &&
          b <= k
        ))
          fail(
            `highlight lines ${a} to ${b} are not lines of the code (1 to ${k})`,
          );
      }
    },
    items: (p) => [["code", 1, [p.file, ...lines(p.code)]]],
  },
  codediff: {
    check: (p, n) => {
      text("codediff", p.lang, "a lang");
      code("codediff", p.before, "a before");
      code("codediff", p.after, "an after");
      at(p.at, n);
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

// The props a visual must hold, for the scene's `n` sentences; throws why not.
export function checkVisual(visual, n) {
  object(visual, "visual");
  const v = VISUALS[visual.component];
  if (!v) fail(`unknown component ${visual.component}`);
  v.check(visual.props ?? {}, n);
}
