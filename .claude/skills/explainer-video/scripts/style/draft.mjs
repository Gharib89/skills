// Style extraction's second half: the roles Claude assigned from the measured
// candidates turned into a draft style profile that passes contrast by role.
//
//   node draft.mjs <run-folder> <name>
//
// Reads <run>/style-draft/candidates.json and roles.json, which maps a colour
// token to `{ "candidate": "<id>", "why": "<one line>" }`; `bg` and `text` are
// required. A token with no role is derived from the default profile: the
// neutrals (panel, chip, line, rule, muted, faint) mixed in OKLab between
// `text` and `bg` where the default profile sets them, the hues (accent, ok,
// warn, stop) at the default profile's hue and chroma, re-lit to its contrast
// on this `bg`. A token under its contrast floor is then moved in OKLCH
// lightness, hue and chroma kept, to the nearest value passing on every
// surface its role sits on. Type, layout, motion, look and effects are the
// default profile's.
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
import { skill } from "../lib/tools.mjs";

const [run, name] = process.argv.slice(2);
if (!run || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name ?? "")) {
  console.error("usage: node draft.mjs <run-folder> <kebab-case-name>");
  process.exit(2);
}
const dir = path.join(run, "style-draft");
const read = (f) => JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
const found = read("candidates.json");
const roles = read("roles.json");
const base = JSON.parse(
  fs.readFileSync(path.join(skill, "styles", `${FALLBACK}.json`), "utf8"),
);
const TOKENS = Object.keys(base.colors);
const NEUTRAL = ["panel", "chip", "line", "rule", "muted", "faint"];

const errors = [];
const byId = new Map(
  [...found.surfaces, ...found.accents].map((c) => [c.id, c]),
);
for (const [t, r] of Object.entries(roles)) {
  if (!TOKENS.includes(t))
    errors.push(`style role ${t}: not a token (${TOKENS.join(", ")})`);
  else if (!byId.has(r?.candidate))
    errors.push(`style role ${t}: no candidate ${r?.candidate}`);
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
for (const [t, r] of Object.entries(roles)) {
  const c = byId.get(r.candidate);
  colors[t] = c.hex;
  marks[t] = {
    mark: "measured",
    candidate: c.id,
    images: c.images,
    why: r.why,
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
    // Where the default profile sets this token between its text and bg.
    const at = (oklab(base.colors[t])[0] - tL) / (bL - tL);
    colors[t] = fromOklab(text.map((v, i) => v + at * (bg[i] - v)));
    marks[t] = {
      mark: "derived",
      why: `mixed between text and bg as ${FALLBACK}'s ${t}`,
    };
  } else {
    // The default's hue and chroma at the lightness, on the side away from
    // bg, nearest the contrast the default holds on its own bg.
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
    const s = role.on.find((s) => contrast(colors[t], colors[s]) < min);
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
    const r = (a, b) => contrast(a, b).toFixed(2);
    marks[t] = {
      mark: "adjusted",
      was: colors[t],
      from: marks[t].mark,
      why: `${t} on ${s} ${r(colors[t], colors[s])}:1 under ${min}:1, moved to ${r(moved, colors[s])}:1`,
    };
    colors[t] = moved;
  }

const profile = {
  ...base,
  name,
  label: name,
  source: `Extracted from ${found.sources.join(", ")}`,
  colors: Object.fromEntries(TOKENS.map((t) => [t, colors[t]])),
  marks: Object.fromEntries(TOKENS.map((t) => [t, marks[t]])),
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
console.log(`style: draft ${name} -> ${out}`);
