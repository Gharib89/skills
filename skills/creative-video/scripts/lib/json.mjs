// The shapes of the run folder's JSON files, as their writers give them, and
// of the skill's own data files (setup/rows.json, narrators.json), and
// the loader that holds a file to its shape, so a malformed file is refused as
// `<file>: is missing`, `<file>: is not valid JSON (...)` or
// `<file>: <field> <problem>`, which the stage prints after its own prefix,
// and never reaches a stage as a TypeError. A shape lists the fields some
// reader dereferences; a reader that defaults a missing field leaves that
// field out of the shape, or wraps it in `opt`.
import fs from "node:fs";
import path from "node:path";

// A shape returns null for a value it accepts, else [field, problem].
const field = (at, key) => (at ? `${at}.${key}` : key);
const text = (v, at) => (typeof v === "string" ? null : [at, "is not text"]);
const number = (v, at) => (Number.isFinite(v) ? null : [at, "is not a number"]);
// Text a reader matches whole words against: an empty or punctuation-only
// entry would match at every word boundary.
const word = (v, at) =>
  text(v, at) ??
  (/[\p{L}\p{N}]/u.test(v) ? null : [at, "has no letter or digit"]);
const opt = (shape) => (v, at) => (v === undefined ? null : shape(v, at));
const isObject = (v) => !!v && typeof v === "object" && !Array.isArray(v);
const list = (of) => (v, at) => {
  if (!Array.isArray(v)) return [at, "is not a list"];
  for (const [i, x] of v.entries()) {
    const bad = of(x, `${at}[${i}]`);
    if (bad) return bad;
  }
  return null;
};
const obj = (fields) => (v, at) => {
  if (!isObject(v)) return [at, "is not an object"];
  for (const [k, shape] of Object.entries(fields)) {
    const bad = shape(v[k], field(at, k));
    if (bad) return bad;
  }
  return null;
};
// An object keyed by a name, every value held to `of`.
const map = (of) => (v, at) => {
  if (!isObject(v)) return [at, "is not an object"];
  for (const [k, x] of Object.entries(v)) {
    const bad = of(x, field(at, k));
    if (bad) return bad;
  }
  return null;
};

const words = list(obj({ text, start: number, end: number }));

// One shape per file, keyed by its path in the run folder or the skill.
export const SHAPES = {
  // The setup catalogue: every reader keys a row by its id and kind.
  "setup/rows.json": obj({ rows: list(obj({ id: text, kind: text })) }),
  // The narrators setup and the voice stage pick from.
  "narrators.json": obj({
    narrators: list(
      obj({ id: text, language: text, backend: text, voice: text }),
    ),
  }),
  // The brief: the voice stage reads its length, the gates stage its must and
  // avoid words.
  "brief.json": obj({
    length: number,
    must: opt(list(word)),
    avoid: opt(list(word)),
  }),
  // The gates stage's record: what it is of and each gate's verdict, which the
  // render reads to refuse a project the gates have not passed.
  "gates.json": obj({
    inputs: text,
    script: text,
    attempts: opt(number),
    gates: map(obj({ status: text })),
  }),
  // The voice stage's input.
  "script.json": obj({
    language: text,
    narrator: opt(text),
    scenes: list(obj({ id: text, narration: list(text) })),
  }),
  // The voice stage.
  "voice.json": obj({
    narrator: text,
    language: text,
    scenes: list(
      obj({
        id: text,
        audio: text,
        duration: number,
        words,
        qc: obj({ failures: list(text) }),
      }),
    ),
  }),
  // The timing stage, read by the root and the render.
  "timeline.json": obj({
    voice: text,
    total: number,
    scenes: list(obj({ id: text, start: number, duration: number })),
    cues: list(obj({ start: number, end: number, text })),
  }),
  // The source snapshot.
  "snapshots/sources.json": obj({
    minutes: number,
    budget: number,
    sources: list(
      obj({
        id: text,
        kind: text,
        source: text,
        snapshot: text,
        share: number,
      }),
    ),
  }),
};

// `name` in run folder `run`, parsed and held to its shape. Throws
// `<name>: is missing`, or what `parseJson` throws.
export function readJson(run, name) {
  const file = path.join(run, name);
  if (!fs.existsSync(file)) throw new Error(`${name}: is missing`);
  return parseJson(name, fs.readFileSync(file, "utf8"));
}

// `body`, the text of run-folder file `name`, parsed and held to its shape.
// Throws `<name>: is not valid JSON (...)` or `<name>: <field> <problem>`.
export function parseJson(name, body) {
  let v;
  try {
    v = JSON.parse(body);
  } catch (e) {
    throw new Error(`${name}: is not valid JSON (${e.message})`);
  }
  const bad = SHAPES[name](v, "");
  if (bad) throw new Error(`${name}: ${bad[0] ? `${bad[0]} ` : ""}${bad[1]}`);
  return v;
}

// `name` held to its shape, or null when the run folder has none.
export const maybeJson = (run, name) =>
  fs.existsSync(path.join(run, name)) ? readJson(run, name) : null;
