// A draft profile's visual grammar, and how each field of it was reached: the
// seam and grain fields a reference video's measured motion sets, the fields
// the agent judged from the video's frame strips (`grammar.json`), and every
// other field left to the default. A field's mark is `measured`, `judged` or,
// with no entry in the grammar, `default`.
import { grammar } from "../lib/style.mjs";

// Every field a grammar states, by its path under `grammar`.
export const FIELD_PATHS = [
  "layout",
  "seams.family",
  "seams.duration",
  "seams.blur",
  "camera.family",
  "camera.scale",
  "camera.duration",
  "type.family",
  "type.stagger",
  "ease",
  "texture.surface",
  "texture.overlays",
  "texture.grain",
  "texture.fieldBlur",
  "texture.depthBlur",
  "bans",
];

// Cuts a minute at or under which a seam takes its longest (0.4 s), and at or
// over which its shortest (0.2 s), the range between by line.
const SLOW = 6;
const FAST = 30;
// The seam's peak blur at a blur at cuts of 1, in px (the knob's top), and the
// blur in px under which the cuts read as plain cuts.
const BLUR_PX = 24;
const PLAIN = 2;
// The grain overlay's opacity at a grain of 1 (the knob's top).
const GRAIN_OPACITY = 0.3;

const round = (v, d) => Math.round(v * 10 ** d) / 10 ** d;

// The fields a video's `motion` ({ cutsPerMinute, blurAtCuts, grain }) sets,
// as `{ path: { value, why } }`: whether the cuts are blurred, how long a seam
// runs for the pace of the cuts, the blur, and the grain's opacity.
export function measuredFields({ cutsPerMinute, blurAtCuts, grain }) {
  const px = Math.round(blurAtCuts * BLUR_PX);
  const out = {
    "texture.grain": {
      value: round(grain * GRAIN_OPACITY, 3),
      why: `grain ${grain} of the reference video's flat areas`,
    },
  };
  if (px < PLAIN) {
    out["seams.family"] = {
      value: "cut",
      why: `blur ${blurAtCuts} at the reference video's cuts: plain cuts`,
    };
    return out;
  }
  const pace = Math.min(1, Math.max(0, (cutsPerMinute - SLOW) / (FAST - SLOW)));
  return {
    "seams.family": {
      value: "velocity",
      why: `blur ${blurAtCuts} at the reference video's cuts`,
    },
    "seams.blur": {
      value: px,
      why: `blur ${blurAtCuts} at the reference video's cuts, ${px} px`,
    },
    "seams.duration": {
      value: round(0.4 - pace * 0.2, 2),
      why: `${cutsPerMinute} cuts/min in the reference video`,
    },
    ...out,
  };
}

// The agent's `grammar.json` read: `{ path: { value, why } }` for the fields it
// judged. Returns the problems, one line each, naming the path.
export function judgedProblems(judged, measured) {
  const out = [];
  for (const [p, f] of Object.entries(judged)) {
    if (!FIELD_PATHS.includes(p))
      out.push(
        `style grammar ${p}: not a grammar field (${FIELD_PATHS.join(", ")})`,
      );
    else if (p in measured)
      out.push(
        `style grammar ${p}: measured from the video, leave it out of grammar.json`,
      );
    else if (typeof f?.why !== "string" || !/^[^\n]*\S[^\n]*$/.test(f.why))
      out.push(
        `style grammar ${p}: needs a one-line why, what the frame strips show`,
      );
    else if (f.value === undefined)
      out.push(`style grammar ${p}: needs a value`);
  }
  return out;
}

// `{ grammar, grammarMarks }` from the measured and judged fields: the nested
// grammar block a profile carries (a field with knobs an object over its
// `family`) and each field's mark and why. No field at all is no grammar.
export function grammarOf(measured, judged) {
  const grammar = {};
  const marks = {};
  const put = (fields, mark) => {
    for (const [p, { value, why }] of Object.entries(fields)) {
      const [field, knob] = p.split(".");
      if (knob) {
        const held = grammar[field];
        grammar[field] = {
          ...(typeof held === "string" ? { family: held } : held),
          [knob]: value,
        };
      } else grammar[field] = value;
      marks[p] = { mark, why };
    }
  };
  put(measured, "measured");
  put(judged, "judged");
  return Object.keys(marks).length ? { grammar, grammarMarks: marks } : {};
}

// The style card's grammar rows, one per field in `FIELD_PATHS` order:
// `{ field, value, mark, why }`, the value as the profile plays it as text.
// A field the profile's grammar states carries its mark (`bundled` when the
// profile gives none); a field it leaves out is `default`, whatever a mark says.
export function grammarRows(profile) {
  const played = grammar(profile);
  const own = profile.grammar ?? {};
  return FIELD_PATHS.map((p) => {
    const [field, knob] = p.split(".");
    const held = own[field];
    const stated = knob
      ? typeof held === "string"
        ? knob === "family"
        : held !== null && typeof held === "object" && Object.hasOwn(held, knob)
      : Object.hasOwn(own, field);
    const value = knob ? played[field][knob] : played[field];
    const mark = profile.grammarMarks?.[p];
    return {
      field: p,
      value: Array.isArray(value) ? value.join(", ") || "none" : String(value),
      mark: stated ? (mark?.mark ?? "bundled") : "default",
      why: stated ? (mark?.why ?? "") : "",
    };
  });
}
