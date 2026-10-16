// Style profiles: one JSON file each, looked up in three stores, project first:
// `explainers/.styles/`, the user config store's `styles/`, then the bundled
// `styles/`. A store's `default` file names its default profile; with none
// named anywhere the run takes `claude-code`. Every profile is checked for
// contrast by role when it loads, and a failure refuses the run.
import fs from "node:fs";
import path from "node:path";
import { userDirs } from "./paths.mjs";
import { skill } from "./tools.mjs";

export const FALLBACK = "claude-code";

// The Arabic type role beside each Latin one, and the Arabic family that
// companions a font of each class (#678's lists, first of each).
export const ARABIC = { title: "arTitle", text: "arText" };
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

// The effects a profile may allow, each a GSAP tween in the composition (an
// effect comes only from a commercial-safe source, ADR 0012): `draw` strokes
// a flow's arrows on; `highlight` marks the code lines a sentence names. A
// profile with no `effects` allows none.
const EFFECTS = ["draw", "highlight"];
const LOOKS = ["clean", "sketch"];

// The profile's look and effects, refused by name when unknown.
function features(profile) {
  const refuse = (why) => {
    throw new Error(`style profile ${profile.name}: ${why}`);
  };
  const look = profile.look ?? "clean";
  if (!LOOKS.includes(look))
    refuse(`look ${look} is not ${LOOKS.join(" or ")}`);
  const effects = profile.effects ?? [];
  if (!Array.isArray(effects)) refuse("effects is not a list");
  for (const e of effects)
    if (!EFFECTS.includes(e))
      refuse(`effects: ${e} is not an effect (${EFFECTS.join(", ")})`);
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

// The profile a run uses: `<run>/style.json` when the run already holds the
// one it asks for, else the named or default profile from the stores, copied
// into the run so a later edit to the store never changes this video.
export function loadStyle(run, name, dirs = userDirs()) {
  const own = path.join(run, "style.json");
  let profile = fs.existsSync(own)
    ? JSON.parse(fs.readFileSync(own, "utf8"))
    : null;
  if (!profile || (name && profile.name !== name)) {
    const list = stores(path.dirname(path.resolve(run)), dirs);
    const want = name ?? defaultStyle(list);
    const file = list
      .map((d) => path.join(d, `${want}.json`))
      .find((f) => fs.existsSync(f));
    if (!file)
      throw new Error(`no style profile ${want} in ${list.join(", ")}`);
    profile = JSON.parse(fs.readFileSync(file, "utf8"));
    profile.name = want;
  }
  validate(profile);
  fs.writeFileSync(own, JSON.stringify(profile, null, 2) + "\n");
  return profile;
}

// Every check a profile passes at load: contrast by role, its gates only
// tightening, its look and effects known.
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
