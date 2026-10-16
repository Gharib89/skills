// Style extraction's second half: the roles Claude assigned from the measured
// colour candidates turned into a draft style profile that passes contrast by
// role.
//
//   node draft.mjs <run-folder> <name>
//
// Reads <run>/style-draft/candidates.json and roles.json, which maps a colour
// token to `{ "candidate": "<id>", "why": "<one line>" }`; `bg` and `text` are
// required. A token with no role is derived from the bundled `claude-code`
// profile: the neutrals (panel, chip, line, rule, muted, faint) mixed in OKLab
// between `text` and `bg` where `claude-code` sets them, the hues (accent, ok,
// warn, stop) at its hue and chroma, re-lit to its contrast on this `bg`. A
// token under its contrast floor is then moved in OKLCH lightness, hue and
// chroma kept, to the nearest value passing on every surface its role sits on.
// Type, layout, motion, look and effects are `claude-code`'s.
// stdout: `style <token>: <hex> · <measured|derived|adjusted> · <why>` per
//         token, then `style: draft <name> -> <file>`
// writes: <run>/style-draft/<name>.json, each token's mark under `marks`, and
//         deletes <run>/style-draft/refs/
// exit:   0 written · 1 a role refused or no passing value, `style ...: <why>`
//         on stderr, nothing written · 2 usage
import fs from "node:fs";
import path from "node:path";
import {
  FALLBACK,
  ROLES,
  contrast,
  failures,
  floors,
  fromOklab,
  oklab,
} from "../lib/style.mjs";
import {
  LICENCES,
  catalogue,
  dest,
  installFont,
  loadBackend,
  skill,
} from "../lib/tools.mjs";

const [run, name] = process.argv.slice(2);
if (!run || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name ?? "")) {
  console.error("usage: node draft.mjs <run-folder> <kebab-case-name>");
  process.exit(2);
}
const dir = path.join(run, "style-draft");
const read = (f) => JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
const found = read("candidates.json");
const { fonts: replacements = {}, ...roles } = read("roles.json");
const base = JSON.parse(
  fs.readFileSync(path.join(skill, "styles", `${FALLBACK}.json`), "utf8"),
);
const TOKENS = Object.keys(base.colors);
const NEUTRAL = ["panel", "chip", "line", "rule", "muted", "faint"];
// What the profile's `source` calls each kind measure took.
const KIND_WORD = {
  image: "screenshot",
  page: "website",
  pdf: "deck",
  pptx: "deck",
  video: "video",
};

const errors = [];
const byId = new Map(
  [...found.surfaces, ...found.accents].map((c) => [c.id, c]),
);
for (const [t, pick] of Object.entries(roles)) {
  if (!TOKENS.includes(t))
    errors.push(`style role ${t}: not a token (${TOKENS.join(", ")})`);
  else if (!byId.has(pick?.candidate))
    errors.push(`style role ${t}: no candidate ${pick?.candidate}`);
  else if (typeof pick.why !== "string" || !/^[^\n]*\S[^\n]*$/.test(pick.why))
    errors.push(
      `style role ${t}: needs a one-line why, where the images show it`,
    );
}
for (const t of ["bg", "text"])
  if (!roles[t])
    errors.push(
      `style role ${t}: required, every reference image shows a ground and its text`,
    );
if (errors.length) {
  for (const e of errors) console.error(e);
  process.exit(1);
}

const colors = {};
const marks = {};
for (const [t, pick] of Object.entries(roles)) {
  const c = byId.get(pick.candidate);
  colors[t] = c.hex;
  marks[t] = {
    mark: "measured",
    candidate: c.id,
    images: c.images,
    ...(c.declared && { declared: true }),
    why: pick.why,
  };
}

const lch = (hex) => {
  const [L, a, b] = oklab(hex);
  return [L, Math.hypot(a, b), Math.atan2(b, a)];
};
const fromLch = (L, C, h) => fromOklab([L, C * Math.cos(h), C * Math.sin(h)]);
const [tL, bL] = [oklab(base.colors.text)[0], oklab(base.colors.bg)[0]];
const [text, bg] = [oklab(colors.text), oklab(colors.bg)];
const light = bg[0] > 0.5;
for (const t of TOKENS.filter((t) => !colors[t])) {
  if (NEUTRAL.includes(t)) {
    // Where `claude-code` sets this token between its text and bg.
    const at = (oklab(base.colors[t])[0] - tL) / (bL - tL);
    colors[t] = fromOklab(text.map((v, i) => v + at * (bg[i] - v)));
    marks[t] = {
      mark: "derived",
      why: `mixed between text and bg as ${FALLBACK}'s ${t}`,
    };
  } else {
    // `claude-code`'s hue and chroma at the lightness, on the side away from
    // bg, nearest the contrast it holds on its own bg.
    const [, C, h] = lch(base.colors[t]);
    const want = contrast(base.colors[t], base.colors.bg);
    let best;
    for (let i = 0; i <= 1000; i++) {
      const L = i / 1000;
      if (light ? L >= bg[0] : L <= bg[0]) continue;
      const hex = fromLch(L, C, h);
      const off = Math.abs(contrast(hex, colors.bg) - want);
      if (!best || off < best.off) best = { hex, off };
    }
    colors[t] = best.hex;
    marks[t] = {
      mark: "derived",
      why: `${FALLBACK}'s ${t} hue, re-lit for this bg`,
    };
  }
}

// Each token under its role's floor moves to the nearest lightness passing on
// every surface the role sits on.
const floor = floors({ name }).contrast;
for (const role of ROLES)
  for (const t of role.tokens) {
    const min = floor[role.floor];
    const passes = (hex) =>
      role.on.every((s) => contrast(hex, colors[s]) >= min);
    if (passes(colors[t])) continue;
    const surface = role.on.find((s) => contrast(colors[t], colors[s]) < min);
    const [L, C, h] = lch(colors[t]);
    let moved;
    for (let d = 1; d <= 1000 && !moved; d++)
      for (const next of [L - d / 1000, L + d / 1000])
        if (!moved && next >= 0 && next <= 1 && passes(fromLch(next, C, h)))
          moved = fromLch(next, C, h);
    if (!moved) {
      console.error(
        `style ${t}: no lightness passes ${min}:1 on ${role.on.join(" and ")}`,
      );
      process.exit(1);
    }
    const ratio = (hex) => contrast(hex, colors[surface]).toFixed(2);
    marks[t] = {
      mark: "adjusted",
      was: colors[t],
      from: marks[t].mark,
      why: `${t} on ${surface} ${ratio(colors[t])}:1 under ${min}:1, moved to ${ratio(moved)}:1`,
    };
    colors[t] = moved;
  }

// Type: the first family a source declares per role plays it when Fontsource
// holds it under an admitted licence, else the replacement roles.json names
// for it under `fonts`, confirmed on Fontsource, admitted and of its class:
// the stack's generic family, else the class the replacement names. The
// Arabic role beside it takes its class's companion (#678's lists, first).
const CLASS = {
  serif: "serif",
  "ui-serif": "serif",
  sans: "sans",
  "sans-serif": "sans",
  "system-ui": "sans",
  "ui-sans-serif": "sans",
  "ui-rounded": "sans",
  mono: "mono",
  monospace: "mono",
  "ui-monospace": "mono",
  display: "display",
  handwriting: "display",
  cursive: "display",
  fantasy: "display",
};
const COMPANION = {
  serif: "noto-naskh-arabic",
  sans: "ibm-plex-sans-arabic",
  mono: "ibm-plex-sans-arabic",
  display: "noto-kufi-arabic",
};
const ARABIC = { title: "arTitle", text: "arText" };
const slug = (family) =>
  family
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
const nearest = (w, ws) =>
  ws.reduce((a, b) => (Math.abs(b - w) < Math.abs(a - w) ? b : a));
const admitted = (meta) => LICENCES.includes(meta.license);
const backend = await loadBackend();

// The Fontsource family a declared font becomes and its mark, or why not.
async function played(f) {
  const own = await backend.fontMeta(slug(f.family));
  if (own && admitted(own))
    return {
      meta: own,
      mark: {
        mark: "measured",
        why: `the source's ${f.role} font, ${own.license}`,
      },
    };
  const pick = replacements[f.family];
  if (!pick?.font || !/^[^\n]*\S[^\n]*$/.test(pick.why ?? ""))
    return `${own ? `licence ${own.license}` : "not on Fontsource"}: name an admitted replacement in roles.json \`fonts\`, { "font": "<Fontsource id>", "why": "<one line>" }`;
  const want = CLASS[f.generic] ?? CLASS[pick.class];
  if (!want)
    return "its stack names no generic family: give its class (serif, sans, mono or display) as the replacement's `class`";
  const meta = await backend.fontMeta(pick.font);
  if (!meta) return `Fontsource has no family ${pick.font}`;
  if (!admitted(meta))
    return `${pick.font} has licence ${meta.license}, only ${LICENCES.join(" or ")}`;
  if (CLASS[meta.category] !== want)
    return `${pick.font} is ${CLASS[meta.category]}, the source's is ${want}`;
  return { meta, mark: { mark: "replaced", was: f.family, why: pick.why } };
}

const type = structuredClone(base.type);
const carried = new Map();
for (const f of found.fonts.filter(
  (f, i, all) => all.findIndex((g) => g.role === f.role) === i,
)) {
  const got = await played(f);
  if (typeof got === "string") {
    errors.push(`style font ${f.family}: ${got}`);
    continue;
  }
  const { meta, mark } = got;
  const font = meta.id;
  const cls = CLASS[meta.category];
  // A catalogue family plays a weight setup installs; any other is fetched at
  // the weight Fontsource holds nearest the bundled role's.
  const row = catalogue().find((r) => r.kind === "font" && r.family === font);
  const weight = nearest(
    base.type[f.role].weight,
    row ? row.files.map((x) => +x.match(/-(\d+)-/)[1]) : meta.weights,
  );
  type[f.role] = { font, weight, ...mark };
  const ar = ARABIC[f.role];
  type[ar] = {
    ...base.type[ar],
    font: COMPANION[cls],
    mark: "derived",
    why: `the ${cls} companion of ${font}`,
  };
  if (row) continue;
  const fetched = carried.get(font) ?? {
    id: `font:${font}`,
    kind: "font",
    family: font,
    version: meta.npmVersion,
    files: [],
    licence: meta.license,
  };
  fetched.files = [...new Set([...fetched.files, `latin-${weight}-normal`])];
  carried.set(font, fetched);
}
if (errors.length) {
  for (const e of errors) console.error(e);
  process.exit(1);
}
// Each carried family into the font store render reads, unless it holds the
// files already.
for (const r of carried.values())
  if (!r.files.every((f) => fs.existsSync(path.join(dest(r), `${f}.woff2`))))
    try {
      await installFont(r, backend);
    } catch (e) {
      console.error(`style font ${r.family}: could not fetch it: ${e.message}`);
      process.exit(1);
    }

const named = found.sources.map(
  ({ kind, source }) => `${KIND_WORD[kind]} ${source}`,
);
const profile = {
  ...base,
  name,
  label: name,
  source: `Extracted from ${named.join(", ")}`,
  colors: Object.fromEntries(TOKENS.map((t) => [t, colors[t]])),
  marks: Object.fromEntries(TOKENS.map((t) => [t, marks[t]])),
  type,
  ...(carried.size && { fonts: [...carried.values()] }),
};
const bad = failures(profile);
if (bad.length) {
  console.error(`style: the draft fails contrast: ${bad.join("; ")}`);
  process.exit(1);
}
const out = path.join(dir, `${name}.json`);
fs.writeFileSync(out, JSON.stringify(profile, null, 2) + "\n");
// Reference images may be a confidential deck's pages: the draft is all that
// stays.
fs.rmSync(path.join(dir, "refs"), { recursive: true, force: true });
for (const t of TOKENS)
  console.log(`style ${t}: ${colors[t]} · ${marks[t].mark} · ${marks[t].why}`);
for (const [r, { font, mark, why }] of Object.entries(type))
  if (mark) console.log(`style type ${r}: ${font} · ${mark} · ${why}`);
console.log(`style: draft ${name} -> ${out}`);
