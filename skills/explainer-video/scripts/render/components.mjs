// The scene components: each one's markup, scoped CSS and tweens, and the
// helpers they share with the page composer in compose.mjs.
import crypto from "node:crypto";
import { diff, lines } from "../lib/visuals.mjs";

// A code line's height: 30 px at 1.5.
const LH = 45;

export const esc = (s) =>
  String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

// A sketch look draws each box's outline with rough.js, at the box's own seed;
// a clean look draws it in CSS.
const sketched = (look, d) =>
  look === "sketch"
    ? `<svg class="sk" viewBox="0 0 ${d.w} ${d.h}" preserveAspectRatio="none"><path class="f" d="${d.fill}"/><path class="s" d="${d.stroke}"/></svg>`
    : "";
const sketchCss = (look) =>
  look === "sketch"
    ? `.sk { position: absolute; inset: 0; width: 100%; height: 100%; }
.sk .f { fill: var(--panel); }
.sk .s { fill: none; stroke: var(--rule); stroke-width: 2.5; }`
    : "";
const boxCss = (look) =>
  look === "sketch"
    ? "position: relative;"
    : "position: relative; background: var(--panel); border: 2px solid var(--line); border-radius: 18px;";

// An arrow as one stroke, its head retraced, so `draw` strokes it whole.
const ARROW = [
  [8, 20],
  [86, 20],
  [72, 7],
  [86, 20],
  [72, 33],
];

// Shiki tokens as spans coloured by the `--code-*` variables, which the code
// frame sets from the palette.
const tokens = (line) =>
  line
    .map((t) => `<span style="color:${t.color}">${esc(t.text)}</span>`)
    .join("");
const CODE_VARS = {
  foreground: "text",
  background: "panel",
  "token-constant": "warn",
  "token-string": "ok",
  "token-string-expression": "ok",
  "token-comment": "faint",
  "token-keyword": "accent",
  "token-parameter": "text",
  "token-function": "text",
  "token-punctuation": "muted",
  "token-link": "accent",
};
const codeFrame = (p, f, rows) => ({
  html: `<div class="code rt" dir="ltr"><div class="bar">${esc(p.file ?? p.lang)}</div><div class="body">${rows}</div></div>`,
  css: `.code { position: absolute; left: 0; top: 0; width: 1680px; box-sizing: border-box; background: var(--panel); border: 2px solid var(--line); border-radius: 18px; overflow: hidden; ${Object.entries(
    CODE_VARS,
  )
    .map(([k, v]) => `--code-${k}: var(--${v});`)
    .join(" ")} }
.bar { height: 56px; border-bottom: 1px solid var(--line); display: flex; align-items: center; padding: 0 28px; font: 400 24px ${f.code}; color: var(--muted); }
.body { position: relative; padding: 28px 44px; font: 400 30px/${LH}px ${f.code}; color: var(--code-foreground); }
.ln { position: relative; height: ${LH}px; white-space: pre; overflow: hidden; }
.hl { position: absolute; left: 16px; right: 16px; background: var(--chip); border-radius: 6px; }
.add { box-shadow: inset 6px 0 var(--ok); }
.del { box-shadow: inset 6px 0 var(--stop); }`,
});

// Each component: its markup, its scoped CSS, what reveals when, as [selector,
// sentence number, spring class] triples (`settle` when left out; only the
// `spring` motion reads it), and its other tweens, as [selector, from, to,
// sentence number]. `x` holds the profile's look and allowed effects, Shiki's
// tokens and rough.js outlines.
export const COMPONENTS = {
  title: (p, f) => ({
    html: `<div class="stack">${p.kicker ? `<div class="kick r0">${f.t(p.kicker)}</div>` : ""}<div class="big r0">${f.tt(p.title)}</div>${p.subtitle ? `<div class="sub r0">${f.t(p.subtitle)}</div>` : ""}</div>`,
    css: `.stack { position: absolute; inset: 0; display: flex; flex-direction: column; justify-content: center; gap: 28px; }
.kick { font: 600 30px ${f.text}; color: var(--accent); letter-spacing: ${f.ls("0.06em")}; text-transform: uppercase; }
.big { font: ${f.titleWeight} 112px/${f.lh(1.08, "title")} ${f.title}; color: var(--text); letter-spacing: ${f.ls("-0.01em")}; max-width: 1600px; }
.sub { font: 400 40px/${f.lh(1.3, "text")} ${f.text}; color: var(--muted); max-width: 1500px; }`,
    reveals: [[".r0", 1, "land"]],
  }),
  cards: (p, f) => ({
    html: `<div class="rail">${p.items
      .map(
        (x, i) =>
          `<div class="card r${i}"><div class="label">${f.t(x.label)}</div><div class="value">${f.tt(x.value)}</div>${x.note ? `<div class="note">${f.t(x.note)}</div>` : ""}</div>`,
      )
      .join("")}</div>`,
    css: `.rail { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; gap: 40px; }
.card { flex: 0 1 380px; min-height: 240px; box-sizing: border-box; background: var(--panel); border: 2px solid var(--line); border-radius: 18px; padding: 34px; }
.label { font: 600 24px ${f.text}; color: var(--muted); letter-spacing: ${f.ls("0.06em")}; text-transform: uppercase; }
.value { margin-top: 26px; font: ${f.titleWeight} 54px/${f.lh(1.1, "title")} ${f.title}; color: var(--text); }
.note { margin-top: 22px; font: 400 28px ${f.note}; color: var(--muted); }`,
    reveals: p.items.map((x, i) => [`.r${i}`, x.at]),
  }),
  terminal: (p, f) => ({
    html: `<div class="term rt" dir="ltr"><div class="bar"><div class="dot"></div><div class="dot"></div><div class="dot"></div>${p.title ? `<span class="name">${esc(p.title)}</span>` : ""}</div><div class="body">${p.lines
      .map((x, i) => `<div class="line r${i}">${esc(x.text)}</div>`)
      .join("")}</div></div>`,
    css: `.term { position: absolute; left: 260px; top: 30px; width: 1240px; height: 600px; box-sizing: border-box; background: var(--panel); border: 2px solid var(--line); border-radius: 18px; overflow: hidden; }
.bar { height: 56px; border-bottom: 1px solid var(--line); display: flex; align-items: center; padding: 0 26px; gap: 12px; font: 400 24px ${f.code}; color: var(--muted); }
.dot { width: 14px; height: 14px; border-radius: 50%; background: var(--line); }
.name { margin-left: 16px; }
.body { padding: 34px 44px; font: 400 34px/1.7 ${f.code}; color: var(--text); }
.line { white-space: pre; }`,
    reveals: [[".rt", 1], ...p.lines.map((x, i) => [`.r${i}`, x.at, "snap"])],
  }),
  flow: async (p, f, x) => {
    const n = p.steps.length;
    const gap = 96;
    const box = { w: Math.floor((1680 - (n - 1) * gap) / n), h: 240 };
    const draw = x.effects.has("draw");
    const shapes = await x.sketch([
      ...p.steps.map((_, i) => ({ rect: [box.w, box.h], key: `node${i}` })),
      ...p.steps
        .slice(1)
        .map((_, i) => ({ line: ARROW, key: `arrow${i + 1}` })),
    ]);
    const arrow = (i) => {
      const d =
        shapes[n + i - 1]?.stroke ??
        `M${ARROW.map((q) => q.join(" ")).join(" L")}`;
      return `<div class="arrow a${i}"><svg viewBox="0 0 96 40" width="96" height="40"><path d="${d}"${draw ? ' pathLength="1" stroke-dasharray="1"' : ""}/></svg></div>`;
    };
    return {
      html: `<div class="flow">${p.steps
        .map(
          (s, i) =>
            `${i ? arrow(i) : ""}<div class="node n${i}">${sketched(x.look, { ...box, ...shapes[i] })}<div class="label">${f.tt(s.label)}</div>${s.note ? `<div class="note">${f.t(s.note)}</div>` : ""}</div>`,
        )
        .join("")}</div>`,
      css: `.flow { position: absolute; inset: 0; display: flex; align-items: center; }
.node { ${boxCss(x.look)} box-sizing: border-box; width: ${box.w}px; height: ${box.h}px; padding: 28px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px; text-align: center; }
.label { position: relative; font: ${f.titleWeight} 46px/${f.lh(1.1, "title")} ${f.title}; color: var(--text); }
.note { position: relative; font: 400 26px ${f.note}; color: var(--muted); }
.arrow { flex: 0 0 ${gap}px; display: flex; justify-content: center; }
.arrow path { fill: none; stroke: var(--rule); stroke-width: 4; stroke-linecap: round; stroke-linejoin: round; }
[dir="rtl"] .arrow svg { transform: scaleX(-1); }
${sketchCss(x.look)}`,
      reveals: [
        ...p.steps.map((s, i) => [`.n${i}`, s.at]),
        ...p.steps.slice(1).map((s, i) => [`.a${i + 1}`, s.at, "snap"]),
      ],
      tweens: draw
        ? p.steps
            .slice(1)
            .map((s, i) => [
              `.a${i + 1} path`,
              { strokeDashoffset: 1 },
              { strokeDashoffset: 0, duration: 0.5, ease: "power1.inOut" },
              s.at,
            ])
        : [],
    };
  },
  panels: async (p, f, x) => {
    const n = p.items.length;
    const box = { w: Math.floor((1680 - (n - 1) * 40) / n), h: 560 };
    const shapes = await x.sketch(
      p.items.map((_, i) => ({ rect: [box.w, box.h], key: `panel${i}` })),
    );
    return {
      html: `<div class="panels">${p.items
        .map(
          (it, i) =>
            `<div class="panel p${i}">${sketched(x.look, { ...box, ...shapes[i] })}<div class="ptitle">${f.tt(it.title)}</div><div class="pbody">${f.t(it.body)}</div></div>`,
        )
        .join("")}</div>`,
      css: `.panels { position: absolute; inset: 0; display: flex; align-items: center; gap: 40px; }
.panel { ${boxCss(x.look)} box-sizing: border-box; width: ${box.w}px; height: ${box.h}px; padding: 48px; text-align: start; }
.ptitle { position: relative; font: ${f.titleWeight} 52px/${f.lh(1.15, "title")} ${f.title}; color: var(--text); }
.pbody { position: relative; margin-top: 28px; font: 400 36px/${f.lh(1.4, "text")} ${f.text}; color: var(--muted); }
${sketchCss(x.look)}`,
      reveals: p.items.map((it, i) => [`.p${i}`, it.at]),
    };
  },
  list: (p, f) => ({
    html: `<div class="list">${p.title ? `<div class="ltitle lt">${f.tt(p.title)}</div>` : ""}${p.items
      .map(
        (it, i) =>
          `<div class="item i${i}"><div class="dot"></div><div class="itext">${f.t(it.text)}</div></div>`,
      )
      .join("")}</div>`,
    css: `.list { position: absolute; inset: 0; display: flex; flex-direction: column; justify-content: center; gap: 26px; text-align: start; }
.ltitle { font: ${f.titleWeight} 60px/${f.lh(1.1, "title")} ${f.title}; color: var(--text); margin-bottom: 14px; }
.item { display: flex; align-items: center; gap: 28px; }
.dot { flex: 0 0 16px; height: 16px; border-radius: 4px; background: var(--accent); }
.itext { font: 400 42px/${f.lh(1.3, "text")} ${f.text}; color: var(--text); }`,
    reveals: [
      ...(p.title ? [[".lt", 1, "land"]] : []),
      ...p.items.map((it, i) => [`.i${i}`, it.at, "snap"]),
    ],
  }),
  code: async (p, f, x) => {
    const rows = await x.highlight(p.code, p.lang);
    const marks = x.effects.has("highlight") ? (p.highlights ?? []) : [];
    const bars = marks
      .map(
        (h, k) =>
          `<div class="hl hl${k}" style="top: ${28 + (h.lines[0] - 1) * LH}px; height: ${(h.lines[1] - h.lines[0] + 1) * LH}px"></div>`,
      )
      .join("");
    return {
      ...codeFrame(
        p,
        f,
        bars +
          rows.map((row) => `<div class="ln">${tokens(row)}</div>`).join(""),
      ),
      reveals: [[".rt", 1]],
      tweens: marks.map((h, k) => [
        `.hl${k}`,
        { opacity: 0 },
        { opacity: 1, duration: 0.35, ease: "power2.out" },
        h.at,
      ]),
    };
  },
  // The diff plays at its sentence: removed lines close and added ones open,
  // their heights tweened, so the kept lines slide into place.
  codediff: async (p, f, x) => {
    const was = await x.highlight(p.before, p.lang);
    const now = await x.highlight(p.after, p.lang);
    const k = { del: 0, add: 0 };
    const shut = { height: 0, opacity: 0 };
    const open = { height: LH, opacity: 1 };
    const go = { duration: 0.5, ease: "power2.inOut" };
    const tweens = [];
    const rows = diff(lines(p.before), lines(p.after)).map(([op, i, j]) => {
      if (op === "keep") return `<div class="ln">${tokens(was[i])}</div>`;
      const cls = `${op}${k[op]++}`;
      tweens.push(
        op === "del"
          ? [`.${cls}`, open, { ...shut, ...go }, p.at]
          : [`.${cls}`, shut, { ...open, ...go }, p.at],
      );
      return `<div class="ln ${op} ${cls}">${tokens(op === "del" ? was[i] : now[j])}</div>`;
    });
    return {
      ...codeFrame(p, f, rows.join("")),
      reveals: [[".rt", 1]],
      tweens,
    };
  },
};

// A rough.js seed per element, from its scene and its key, so a render repeats
// exactly and an edit to one scene never moves another's strokes.
export const seed = (id, key) =>
  parseInt(
    crypto
      .createHash("sha256")
      .update(`${id}:${key}`)
      .digest("hex")
      .slice(0, 8),
    16,
  ) || 1;
