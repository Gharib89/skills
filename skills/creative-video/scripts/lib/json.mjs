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
const matchWord = (v, at) =>
  text(v, at) ??
  (/[\p{L}\p{N}]/u.test(v) ? null : [at, "has no letter or digit"]);
const opt = (shape) => (v, at) => (v === undefined ? null : shape(v, at));
const orNull = (shape) => (v, at) => (v === null ? null : shape(v, at));
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
    must: opt(list(matchWord)),
    avoid: opt(list(matchWord)),
  }),
  // The gates stage's record: what it is of and each gate's verdict, which the
  // render reads to refuse a project the gates have not passed, and the
  // critic's rounds, which the next gates run carries on.
  "gates.json": obj({
    inputs: text,
    voice: text,
    attempts: opt(number),
    gates: (v, at) =>
      map(obj({ status: text }))(v, at) ??
      obj({
        critic: opt(obj({ format: number, rounds: list(text), stills: text })),
      })(v, at),
  }),
  // The voice stage's input; the claims check reads each sentence's cites,
  // excerpt ids, which a script voiced alone may leave out. `roles` names each
  // sentence's speaker (lib/kit.mjs), null for the narrator.
  "script.json": obj({
    language: text,
    narrator: opt(text),
    scenes: list(
      obj({
        id: text,
        narration: list(text),
        cites: opt(list(list(text))),
        roles: opt(list(orNull(text))),
      }),
    ),
    // The chapter plan of a video in chapters: each chapter's title, focus and
    // scene ids (render/timing.mjs holds them to the scenes).
    chapters: opt(
      list(obj({ title: text, focus: opt(text), scenes: list(text) })),
    ),
  }),
  // The cast (lib/kit.mjs): each role's narrators.json id per language and
  // the style line it speaks in.
  "project/kit/cast.json": map(obj({ voices: map(text), style: opt(text) })),
  // The sound kit (lib/kit.mjs): the bed and each palette sound by the query
  // the agent writes, the `file` sound/sounds.mjs fills, and what it dropped.
  "project/kit/sound.json": obj({
    bed: opt(
      obj({
        query: matchWord,
        level: number,
        out: opt(list(text)),
        file: opt(text),
      }),
    ),
    palette: opt(list(obj({ event: text, query: matchWord, file: opt(text) }))),
    dropped: opt(list(obj({ event: text, query: text, why: text }))),
  }),
  // The source pack, read by the claims check and the gates.
  "excerpts.json": obj({ excerpts: list(obj({ id: text, text })) }),
  // The support checker's verdicts (agents/support-checker.md).
  "support.json": obj({
    sentences: list(
      obj({
        scene: text,
        n: number,
        text,
        cites: list(text),
        verdict: text,
        why: text,
      }),
    ),
  }),
  // The claims check's record (source/claims.mjs), read by the support gate,
  // and its fix attempts and kept verdicts, read by the next claims check.
  "claims.json": obj({
    passed: opt(text),
    support: opt(
      obj({
        attempts: number,
        verdicts: opt(map(obj({ verdict: text, why: text }))),
      }),
    ),
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
    chapters: opt(
      list(
        obj({
          n: number,
          title: text,
          start: number,
          end: number,
          scenes: list(text),
        }),
      ),
    ),
  }),
  // What the storyboard shows beyond the scenes (board/board.mjs): the video's
  // title, the chapter's focus, the three directions and a title and notes per
  // scene. Which ids it names, and how many, the stage checks.
  "storyboard.json": obj({
    title: text,
    focus: text,
    directions: obj({
      recommended: text,
      picked: text,
      list: list(obj({ id: text, name: text, kind: text })),
    }),
    scenes: map(obj({ title: text, notes: text })),
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
