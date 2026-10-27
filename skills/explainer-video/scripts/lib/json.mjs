// The run folder's JSON files, each read through one loader that checks the
// shape its writer gives it, so a malformed file is refused as
// `<file>: <field> <problem>` and never reaches a stage as a TypeError. A
// shape holds the fields some reader dereferences; a reader that defaults a
// missing field leaves it out, or optional.
import fs from "node:fs";
import path from "node:path";

// A shape answers null for a value it holds, else [field, problem].
const field = (at, key) => (at ? `${at}.${key}` : key);
const text = (v, at) => (typeof v === "string" ? null : [at, "is not text"]);
const number = (v, at) => (Number.isFinite(v) ? null : [at, "is not a number"]);
const opt = (shape) => (v, at) => (v === undefined ? null : shape(v, at));
const nullable = (shape) => (v, at) => (v === null ? null : shape(v, at));
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
// An object of any keys, each value of one shape.
const dict = (of) => (v, at) => {
  if (!isObject(v)) return [at, "is not an object"];
  for (const [k, x] of Object.entries(v)) {
    const bad = of(x, field(at, k));
    if (bad) return bad;
  }
  return null;
};

const words = list(obj({ text, start: number, end: number }));

// One shape per run-folder file, keyed by its path in the run folder.
export const SHAPES = {
  // The brief stage writes every knob; a part's brief is the run's, refocused.
  "brief.json": obj({
    focus: text,
    length: number,
    audience: text,
    language: text,
    style: text,
    voice: text,
    aspect: text,
    score: text,
    must: list(text),
    avoid: list(text),
  }),
  // The compile stage.
  "script.json": obj({
    title: text,
    language: text,
    narrator: opt(text),
    style: opt(text),
    kept: opt(list(text)),
    scenes: list(
      obj({
        id: text,
        title: text,
        role: opt(text),
        seconds: opt(number),
        section: opt(number),
        narration: list(text),
        captions: list(list(obj({ text, words: number }))),
        cites: list(list(text)),
        visual: obj({ component: text, props: opt(obj({})), seam: opt(text) }),
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
  // The render stage, `--stills` included.
  "timeline.json": obj({
    total: number,
    scenes: list(
      obj({
        id: text,
        start: number,
        duration: number,
        slot: number,
        seam: text,
        sentences: list(number),
        words,
      }),
    ),
  }),
  "stills.json": obj({ scenes: list(obj({ id: text, still: text })) }),
  "score.json": obj({ score: text, cues: list(obj({ t: number })) }),
  // The render stage once delivered; the board adds `board`
  // before that, so a manifest may hold either field alone, or neither.
  "manifest.json": obj({
    board: opt(nullable(text)),
    delivered: opt(text),
  }),
  // The source pack; the excerpt reader checks the kinds and the source ids.
  "excerpts.json": obj({
    excerpts: list(obj({ id: text, source: text, locator: text, text })),
    sources: list(obj({ id: text })),
  }),
  // The support-checker agent, per its agent file.
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
  // The script check, read back on its next run.
  "check.json": obj({
    support: obj({
      attempts: number,
      judged: nullable(text),
      verdicts: opt(dict(obj({ verdict: text, why: text }))),
    }),
  }),
  // The video gates, read back on their next run and by the board.
  "gates.json": obj({
    script: text,
    render: text,
    attempts: number,
    gates: dict(obj({ status: text, evidence: list(text) })),
  }),
  // The sampling pass.
  "samples.json": obj({
    scenes: list(obj({ id: text, findings: list(text) })),
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
// `<name>: <field> <problem>`, or `<name>: is not valid JSON (...)`.
export function readJson(run, name) {
  let v;
  try {
    v = JSON.parse(fs.readFileSync(path.join(run, name), "utf8"));
  } catch (e) {
    throw new Error(
      `${name}: ${e.code === "ENOENT" ? "is missing" : `is not valid JSON (${e.message})`}`,
    );
  }
  const bad = SHAPES[name](v, "");
  if (bad) throw new Error(`${name}: ${bad[0] ? `${bad[0]} ` : ""}${bad[1]}`);
  return v;
}

// `name` held to its shape, or null when the run folder has none.
export const maybeJson = (run, name) =>
  fs.existsSync(path.join(run, name)) ? readJson(run, name) : null;
