// Style profiles: one JSON file each, looked up in three stores, project first:
// `explainers/.styles/`, the user config store's `styles/`, then the bundled
// `styles/`. A store's `default` file names its default profile; with none
// named anywhere the run takes `claude-code`. Every profile is checked for
// contrast by role when it loads, and a failure refuses the run.
import fs from "node:fs";
import path from "node:path";
import { userDirs } from "./paths.mjs";
import { skill } from "./tools.mjs";
import { VISUALS } from "./visuals.mjs";

export const FALLBACK = "claude-code";

// The Arabic type role beside each Latin one, and the Arabic family that
// companions a font of each class (#678's lists, first of each).
export const ARABIC = { title: "arTitle", text: "arText" };
// The type roles a video in `language` draws: an Arabic one keeps the Latin
// roles too, for its English terms and its code.
export const typeRoles = (language) => [
  "title",
  "text",
  "code",
  ...(language === "ar" ? Object.values(ARABIC) : []),
];
export const COMPANION = {
  serif: "noto-naskh-arabic",
  sans: "ibm-plex-sans-arabic",
  mono: "ibm-plex-sans-arabic",
  display: "noto-kufi-arabic",
};

// The loudness target the master aims at and the gate judges around.
export const LUFS = -14;

// The skill's gate floors; a profile's `gates` block may only tighten them:
// raise contrast (WCAG 2.1) and layout's text size and safe margin, lower
// loudness's tolerance around -14 LUFS, its true peak in dBTP and the sound
// effects allowed in any minute.
const FLOORS = {
  contrast: { body: 4.5, large: 3 },
  layout: { textPx: 18, margin: 0.05 },
  loudness: { tolerance: 1, peak: -1 },
  sfx: { perMinute: 24 },
};
const LOWER = new Set(["loudness", "sfx"]);

// The floors a run is judged by: the skill's, as the profile tightens them.
export function floors(profile) {
  const refuse = (why) => {
    throw new Error(`style profile ${profile.name}: gates.${why}`);
  };
  const out = structuredClone(FLOORS);
  for (const [g, keys] of Object.entries(profile.gates ?? {})) {
    if (!Object.hasOwn(FLOORS, g)) refuse(`${g}: no such floor`);
    for (const [k, v] of Object.entries(keys ?? {})) {
      if (!Object.hasOwn(FLOORS[g], k)) refuse(`${g}.${k}: no such floor`);
      const f = FLOORS[g][k];
      if (!Number.isFinite(v)) refuse(`${g}.${k}: not a number`);
      if (g === "loudness" && k === "tolerance" && v <= 0)
        refuse(`${g}.${k} ${v} must be above 0`);
      // The master aims half a dB under the peak floor, and loudnorm's TP stops
      // at -9 dBTP.
      if (g === "loudness" && k === "peak" && v < -8.5)
        refuse(`${g}.${k} ${v} is under -8.5, the lowest the master reaches`);
      if (g === "sfx" && !(Number.isInteger(v) && v >= 0))
        refuse(`${g}.${k} ${v} must be a whole number 0 or more`);
      if (LOWER.has(g) ? v > f : v < f)
        refuse(`${g}.${k} ${v} lowers the skill's floor ${f}`);
      out[g][k] = v;
    }
  }
  return out;
}

// Schema 2: `colors`, `type`, an optional `scale` of type-step overrides and
// an optional `grammar` block. Schema 1 (`motion`, `look`, `effects`) is
// refused, with no in-memory migration.
export const SCHEMA = 2;

// The seven type steps in px, each exposed to the composition as
// `--size-<step>`; a profile's `scale` overrides a step, never under the
// layout floor.
export const SCALE = {
  display: 112,
  title: 56,
  heading: 46,
  body: 40,
  code: 32,
  small: 28,
  label: 24,
};

// The grammar: each field a named family, default first, holding the families
// the composer draws today; each later slice adds its family and moves its
// field's default. A field left out takes the default, so a profile states
// only where it departs. A field with knobs takes a bare family name or an
// object `{ family, ...knobs }`; a knob is a number within its range.
const FIELDS = {
  layout: { families: ["bands"] },
  seams: { families: ["cut"], knobs: { duration: [0.2, 0.4], blur: [0, 24] } },
  camera: { families: ["locked"], knobs: { scale: [1.03, 1.12] } },
  type: { families: ["block"], knobs: { stagger: [0.03, 0.08] } },
  ease: { families: ["soft", "spring"] },
};
const SURFACES = ["flat", "sketch"];

// The components a family draws, keyed `<field>.<family>`: a grammar may not
// ban one its own families need. Empty until a family needs a component (the
// `canvas` seams will need `canvas`).
const USES = {};

const own = (v) => (typeof v === "string" ? { family: v } : (v ?? {}));
const or = (list) => list.join(" or ");

// The grammar a profile plays: its own fields over the defaults.
export function grammar(profile) {
  const g = profile.grammar ?? {};
  const out = { bans: g.bans ?? [] };
  for (const [field, { families, knobs }] of Object.entries(FIELDS))
    out[field] = knobs
      ? { family: families[0], ...own(g[field]) }
      : (g[field] ?? families[0]);
  out.texture = { surface: SURFACES[0], ...g.texture };
  return out;
}

// The profile's type steps: the scale, as the profile overrides it.
export const scale = (profile) => ({ ...SCALE, ...profile.scale });

// A grammar that bans a component one of its own families draws is refused.
export function checkBans(g, uses, name) {
  for (const [field, v] of Object.entries(g)) {
    const family = typeof v === "string" ? v : v?.family;
    for (const c of uses[`${field}.${family}`] ?? [])
      if (g.bans?.includes(c))
        throw new Error(
          `style profile ${name}: grammar.${field} ${family} uses the ${c} component, which grammar.bans bans`,
        );
  }
}

// The profile's schema, grammar and type scale, each refused by its field.
function features(profile) {
  const refuse = (why) => {
    throw new Error(`style profile ${profile.name}: ${why}`);
  };
  if (profile.schema !== SCHEMA)
    throw new Error(
      `style profile ${profile.name} is schema ${profile.schema ?? 1}, this version loads schema ${SCHEMA}: set schema to ${SCHEMA}, rename motion to grammar.ease (rise is soft), move look to grammar.texture.surface (clean is flat) and remove effects`,
    );
  for (const [field, v] of Object.entries(profile.grammar ?? {})) {
    if (field === "bans") {
      if (!Array.isArray(v)) refuse("grammar.bans is not a list");
      for (const b of v)
        if (!Object.hasOwn(VISUALS, b))
          refuse(`grammar.bans: ${b} is not a component`);
    } else if (field === "texture") {
      for (const [k, t] of Object.entries(v ?? {})) {
        if (k !== "surface") refuse(`grammar.texture.${k}: no such field`);
        if (!SURFACES.includes(t))
          refuse(`grammar.texture.surface ${t} is not ${or(SURFACES)}`);
      }
    } else if (Object.hasOwn(FIELDS, field)) {
      const { families, knobs = {} } = FIELDS[field];
      const { family = families[0], ...rest } = own(v);
      if (!families.includes(family))
        refuse(`grammar.${field} ${family} is not ${or(families)}`);
      for (const [k, n] of Object.entries(rest)) {
        if (!Object.hasOwn(knobs, k))
          refuse(`grammar.${field}.${k}: no such knob`);
        const [lo, hi] = knobs[k];
        if (!Number.isFinite(n))
          refuse(`grammar.${field}.${k} ${n} is not a number`);
        if (n < lo || n > hi)
          refuse(`grammar.${field}.${k} ${n} is outside ${lo} to ${hi}`);
      }
    } else refuse(`grammar.${field}: no such field`);
  }
  const floor = floors(profile).layout.textPx;
  for (const [step, px] of Object.entries(profile.scale ?? {})) {
    if (!Object.hasOwn(SCALE, step)) refuse(`scale.${step}: no such step`);
    if (!Number.isFinite(px)) refuse(`scale.${step} ${px} is not a number`);
    if (px < floor)
      refuse(`scale.${step} ${px} is under the ${floor} px layout floor`);
  }
  checkBans(grammar(profile), USES, profile.name);
}

// Body text sits on every surface; large or faint text (captions before their
// word, accents, status colours) never on the label chip.
export const ROLES = [
  { floor: "body", tokens: ["text", "muted"], on: ["bg", "panel", "chip"] },
  {
    floor: "large",
    tokens: ["faint", "accent", "ok", "warn", "stop"],
    on: ["bg", "panel"],
  },
];

function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

// OKLab (Björn Ottosson's), where style extraction mixes, compares and re-lights
// colours: `[L, a, b]` from a #rrggbb, and back, each channel clipped to sRGB.
export function oklab(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  const [l, m, s] = [
    0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
    0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
    0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
  ].map(Math.cbrt);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

export function fromOklab([L, a, b]) {
  const [l, m, s] = [
    L + 0.3963377774 * a + 0.2158037573 * b,
    L - 0.1055613458 * a - 0.0638541728 * b,
    L - 0.0894841775 * a - 1.291485548 * b,
  ].map((v) => v ** 3);
  return (
    "#" +
    [
      4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
    ]
      .map((v) => {
        const c = Math.min(1, Math.max(0, v));
        const e = c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055;
        return Math.round(e * 255)
          .toString(16)
          .padStart(2, "0");
      })
      .join("")
  );
}

// Every token pair below its role's floor, as `<token> on <surface> <ratio>:1,
// floor <n>:1`.
export function failures(profile) {
  const c = profile.colors ?? {};
  const out = [];
  for (const role of ROLES) {
    const own = profile.gates?.contrast?.[role.floor];
    if (own !== undefined && !Number.isFinite(own)) {
      out.push(`gates.contrast.${role.floor}: not a number`);
      continue;
    }
    const floor = Math.max(FLOORS.contrast[role.floor], own ?? 0);
    for (const t of role.tokens)
      for (const s of role.on) {
        if (
          !/^#[0-9a-f]{6}$/i.test(c[t] ?? "") ||
          !/^#[0-9a-f]{6}$/i.test(c[s] ?? "")
        ) {
          out.push(`${t} on ${s}: not a #rrggbb colour`);
          continue;
        }
        const r = contrast(c[t], c[s]);
        if (r < floor)
          out.push(`${t} on ${s} ${r.toFixed(2)}:1, floor ${floor}:1`);
      }
  }
  return out;
}

export function stores(explainers, dirs = userDirs()) {
  return [
    path.join(explainers, ".styles"),
    path.join(dirs.config, "styles"),
    path.join(skill, "styles"),
  ];
}

const read = (f) =>
  fs.existsSync(f) ? fs.readFileSync(f, "utf8").trim() || null : null;

// The profile a run takes when it names none: the first store's `default`
// file, else the fallback.
export const defaultStyle = (list) =>
  list.map((d) => read(path.join(d, "default"))).find(Boolean) ?? FALLBACK;

// The profile a run uses, unchecked: `<run>/style.json` when the run already
// holds the one it asks for, else the named or default profile from the
// stores, null when no store holds it.
export function findStyle(run, name, dirs = userDirs()) {
  const own = path.join(run, "style.json");
  const held = fs.existsSync(own)
    ? JSON.parse(fs.readFileSync(own, "utf8"))
    : null;
  if (held && (!name || held.name === name)) return { profile: held };
  const list = stores(path.dirname(path.resolve(run)), dirs);
  const want = name ?? defaultStyle(list);
  const file = list
    .map((d) => path.join(d, `${want}.json`))
    .find((f) => fs.existsSync(f));
  if (!file) return { want, list, profile: null };
  return {
    profile: { ...JSON.parse(fs.readFileSync(file, "utf8")), name: want },
  };
}

// The profile a run uses, checked and copied into the run so a later edit to
// the store never changes this video.
export function loadStyle(run, name, dirs = userDirs()) {
  const own = path.join(run, "style.json");
  const { profile, want, list } = findStyle(run, name, dirs);
  if (!profile)
    throw new Error(`no style profile ${want} in ${list.join(", ")}`);
  validate(profile);
  fs.writeFileSync(own, JSON.stringify(profile, null, 2) + "\n");
  return profile;
}

// Every check a profile passes at load: contrast by role, its gates only
// tightening, schema 2 with its grammar and type scale in range.
export function validate(profile) {
  const bad = failures(profile);
  if (bad.length)
    throw new Error(
      `style profile ${profile.name} fails contrast: ${bad.join("; ")}`,
    );
  floors(profile);
  features(profile);
}

// Where a saved profile goes: the user store when the running copy of the
// skill sits under a user skills directory (a personal copy shadows the
// project's, so the running copy is the install that counts), else the
// project's `explainers/.styles/`.
export function saveScope(skillDir, home) {
  const under = (d) => {
    const rel = path.relative(d, path.resolve(skillDir));
    return !rel.startsWith("..") && !path.isAbsolute(rel);
  };
  return [".claude", ".agents"].some((d) => under(path.join(home, d, "skills")))
    ? "user"
    : "project";
}
