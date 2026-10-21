// The scene components: each one's markup, scoped CSS and tweens, and the
// helpers they share with the page composer in compose.mjs.
import crypto from "node:crypto";
import { WORD_RISE_SECONDS } from "../lib/style.mjs";
import { wholeWords } from "../lib/terms.mjs";
import { diff, lines, readAlong } from "../lib/visuals.mjs";
import { boxCss, esc, paint, sketchCss, sketched } from "./box.mjs";
import { browser } from "./browser.mjs";
import { custom } from "./custom.mjs";
import { diagram } from "./diagram.mjs";
import { excerpt } from "./excerpt.mjs";
import { chart, stat } from "./numbers.mjs";
import { compare, timeline } from "./sequence.mjs";

export { esc };

// The selector of every item a scene can bring into or out of focus: a card, a
// terminal line, a flow step, a panel, a list item.
export const ITEMS = ".card, .line, .node, .panel, .item";

// An arrow as one stroke, its head retraced, so `draw` strokes it whole.
const ARROW = [
  [8, 20],
  [86, 20],
  [72, 7],
  [86, 20],
  [72, 33],
];

// The grammar's callout for an emphasis: an accent ring round one item and a
// leader line ending in a dot, hidden until the emphasis's cue. A box (card,
// step, panel) leads down, a row (terminal line, list item, code lines) leads
// to the end of the line, so the leader never crosses a neighbour.
const callout = (side = "") => `<div class="em${side}"></div>`;
const host = (em, row = "") => (em ? ` em-host${row}` : "");
const CALLOUT_CSS = `.em-host { position: relative; }
.em-host.row { width: fit-content; }
.em { position: absolute; box-sizing: border-box; border: 4px solid var(--accent); border-radius: 24px; opacity: 0; pointer-events: none; }
.em-host > .em { inset: -14px; }
.em-host.row > .em { inset: -4px -14px; border-radius: 14px; }
.em::before, .em::after { content: ""; position: absolute; background: var(--accent); }
.em::before { left: 50%; top: 100%; width: 4px; height: 44px; margin-left: -2px; }
.em::after { left: 50%; top: calc(100% + 44px); width: 16px; height: 16px; margin-left: -8px; border-radius: 50%; }
.em.side::before { left: auto; inset-inline-start: 100%; top: 50%; width: 44px; height: 4px; margin: -2px 0 0; }
.em.side::after { left: auto; inset-inline-start: calc(100% + 44px); top: 50%; margin: -8px 0 0; }`;
// The index of the item an emphasis names, by the text shown for each, or -1.
const emphasised = (e, texts) => (e ? texts.indexOf(e.target) : -1);
// The callout appears on the emphasis's cue.
const reveal = (e) =>
  e
    ? [
        [
          ".em",
          { opacity: 0 },
          { opacity: 1, duration: 0.35, ease: "power2.out" },
          e,
        ],
      ]
    : [];

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
const codeFrame = (p, f, rows, LH, surface) => ({
  html: `<div class="code rt" dir="ltr"><div class="bar">${esc(p.file ?? p.lang)}</div><div class="body">${rows}</div></div>`,
  css: `.code { position: absolute; left: 0; top: 0; width: 1680px; box-sizing: border-box; ${paint(surface)} border: 2px solid var(--line); border-radius: 18px; overflow: hidden; ${Object.entries(
    CODE_VARS,
  )
    .map(([k, v]) => `--code-${k}: var(--${v});`)
    .join(" ")} }
.bar { height: 56px; border-bottom: 1px solid var(--line); display: flex; align-items: center; padding: 0 28px; font: 400 var(--size-label) ${f.code}; color: var(--muted); }
.body { position: relative; padding: 28px 44px; font: 400 var(--size-code)/${LH}px ${f.code}; color: var(--code-foreground); }
.ln { position: relative; height: ${LH}px; white-space: pre; overflow: hidden; }
.add { box-shadow: inset 6px 0 var(--ok); }
.del { box-shadow: inset 6px 0 var(--stop); }`,
});

// A line as one masked span per whole word, numbered `k<n>` from `from`: the
// type family `words` rises each out of its mask. A word is never split, so
// Arabic keeps its joins; `wrap` isolates a Latin run inside it.
const kineticWords = (text, f, wrap, from) => {
  const words = wholeWords(text, f.rtl);
  return {
    html: words
      .map(
        (w, i) =>
          `<span class="w"><span class="wi k${from + i}">${wrap(w)}</span></span>`,
      )
      .join(" "),
    count: from + words.length,
    words,
  };
};
// The mask clips at the line box, so it takes a little padding to keep
// descenders and Arabic marks whole.
const WORD_CSS = `.w { display: inline-block; overflow: hidden; vertical-align: top; padding: 0.15em 0; margin: -0.15em 0; }
.wi { display: inline-block; }`;
// The percent of its own height a word starts below its mask.
const WORD_RISE = 115;

// Each component: its markup, its scoped CSS, what reveals when, as [selector,
// sentence number, spring class] triples (`settle` when left out; only the
// `spring` ease reads it), and its other tweens, as [selector, from, to,
// sentence number]. `x` holds the profile's surface, Shiki's tokens and
// rough.js outlines.
export const COMPONENTS = {
  chart,
  stat,
  timeline,
  compare,
  diagram,
  browser,
  excerpt,
  custom,
  title: (p, f, x) => {
    const kick = p.kicker ? `<div class="kick r0">${f.t(p.kicker)}</div>` : "";
    const css = `.stack { position: absolute; inset: 0; display: flex; flex-direction: column; justify-content: center; gap: 28px; }
.kick { font: 600 var(--size-small) ${f.text}; color: var(--accent); letter-spacing: ${f.ls("0.06em")}; text-transform: uppercase; }
.big { font: ${f.titleWeight} var(--size-display)/${f.lh(1.08, "title")} ${f.title}; color: var(--text); letter-spacing: ${f.ls("-0.01em")}; max-width: 1600px; }
.sub { font: 400 var(--size-body)/${f.lh(1.3, "text")} ${f.text}; color: var(--muted); max-width: 1500px; }`;
    if (!x.type.words)
      return {
        html: `<div class="stack">${kick}<div class="big r0">${f.tt(p.title)}</div>${p.subtitle ? `<div class="sub r0">${f.t(p.subtitle)}</div>` : ""}</div>`,
        css,
        reveals: [[".r0", 1, "land"]],
      };
    // The title, then the subtitle, one masked span per whole word.
    const title = kineticWords(p.title, f, f.tt, 0);
    const sub = p.subtitle
      ? kineticWords(p.subtitle, f, f.t, title.count)
      : { html: "", count: title.count };
    return {
      html: `<div class="stack">${kick}<div class="big">${title.html}</div>${p.subtitle ? `<div class="sub">${sub.html}</div>` : ""}</div>`,
      css: `${css}\n${WORD_CSS}`,
      reveals: kick ? [[".r0", 1, "land"]] : [],
      tweens: Array.from({ length: sub.count }, (_, n) => {
        const blur = n < title.count ? x.type.blur : 0;
        return [
          `.k${n}`,
          {
            yPercent: WORD_RISE,
            opacity: 0,
            ...(blur && { filter: `blur(${blur}px)` }),
          },
          {
            yPercent: 0,
            opacity: 1,
            ...(blur && { filter: "blur(0px)" }),
            duration: WORD_RISE_SECONDS,
            ease: x.type.ease,
            delay: +(n * x.type.stagger).toFixed(6),
          },
          1,
        ];
      }),
    };
  },
  cards: (p, f, x) => {
    const em = emphasised(
      p.emphasis,
      p.items.map((x) => x.label),
    );
    return {
      html: `<div class="rail">${p.items
        .map(
          (x, i) =>
            `<div class="card r${i}${host(i === em)}"><div class="label">${f.t(x.label)}</div><div class="value">${f.tt(x.value)}</div>${x.note ? `<div class="note">${f.t(x.note)}</div>` : ""}${i === em ? callout() : ""}</div>`,
        )
        .join("")}</div>`,
      css: `.rail { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; gap: 40px; }
.card { flex: 0 1 380px; min-height: 240px; box-sizing: border-box; ${paint(x.surface)} border: 2px solid var(--line); border-radius: 18px; padding: 34px; }
.label { font: 600 var(--size-label) ${f.text}; color: var(--muted); letter-spacing: ${f.ls("0.06em")}; text-transform: uppercase; }
.value { margin-top: 26px; font: ${f.titleWeight} var(--size-title)/${f.lh(1.1, "title")} ${f.title}; color: var(--text); }
.note { margin-top: 22px; font: 400 var(--size-small) ${f.note}; color: var(--muted); }
${CALLOUT_CSS}`,
      reveals: p.items.map((x, i) => [`.r${i}`, x]),
      tweens: reveal(p.emphasis),
    };
  },
  terminal: (p, f, x) => {
    const em = emphasised(
      p.emphasis,
      p.lines.map((x) => x.text),
    );
    return {
      html: `<div class="term rt" dir="ltr"><div class="bar"><div class="dot"></div><div class="dot"></div><div class="dot"></div>${p.title ? `<span class="name">${esc(p.title)}</span>` : ""}</div><div class="body">${p.lines
        .map(
          (x, i) =>
            `<div class="line r${i}${host(i === em, " row")}">${esc(x.text)}${i === em ? callout() : ""}</div>`,
        )
        .join("")}</div></div>`,
      css: `.term { position: absolute; left: 260px; top: 30px; width: 1240px; height: 600px; box-sizing: border-box; ${paint(x.surface)} border: 2px solid var(--line); border-radius: 18px; overflow: hidden; }
.bar { height: 56px; border-bottom: 1px solid var(--line); display: flex; align-items: center; padding: 0 26px; gap: 12px; font: 400 var(--size-label) ${f.code}; color: var(--muted); }
.dot { width: 14px; height: 14px; border-radius: 50%; background: var(--line); }
.name { margin-left: 16px; }
.body { padding: 34px 44px; font: 400 var(--size-code)/1.7 ${f.code}; color: var(--text); }
.line { white-space: pre; }
${CALLOUT_CSS}`,
      reveals: [[".rt", 1], ...p.lines.map((x, i) => [`.r${i}`, x, "snap"])],
      tweens: reveal(p.emphasis),
    };
  },
  flow: async (p, f, x) => {
    const n = p.steps.length;
    const em = emphasised(
      p.emphasis,
      p.steps.map((s) => s.label),
    );
    const gap = 96;
    const box = { w: Math.floor((1680 - (n - 1) * gap) / n), h: 240 };
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
      return `<div class="arrow a${i}"><svg viewBox="0 0 96 40" width="96" height="40"><path d="${d}" pathLength="1" stroke-dasharray="1"/></svg></div>`;
    };
    return {
      html: `<div class="flow">${p.steps
        .map(
          (s, i) =>
            `${i ? arrow(i) : ""}<div class="node n${i}${host(i === em)}">${sketched(x.surface, { ...box, ...shapes[i] })}<div class="label">${f.tt(s.label)}</div>${s.note ? `<div class="note">${f.t(s.note)}</div>` : ""}${i === em ? callout() : ""}</div>`,
        )
        .join("")}</div>`,
      css: `.flow { position: absolute; inset: 0; display: flex; align-items: center; }
.node { ${boxCss(x.surface)} box-sizing: border-box; width: ${box.w}px; height: ${box.h}px; padding: 28px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px; text-align: center; }
.label { position: relative; font: ${f.titleWeight} var(--size-heading)/${f.lh(1.1, "title")} ${f.title}; color: var(--text); }
.note { position: relative; font: 400 var(--size-small) ${f.note}; color: var(--muted); }
.arrow { flex: 0 0 ${gap}px; display: flex; justify-content: center; }
.arrow path { fill: none; stroke: var(--rule); stroke-width: 4; stroke-linecap: round; stroke-linejoin: round; }
[dir="rtl"] .arrow svg { transform: scaleX(-1); }
${sketchCss(x.surface)}
${CALLOUT_CSS}`,
      reveals: [
        ...p.steps.map((s, i) => [`.n${i}`, s]),
        ...p.steps.slice(1).map((s, i) => [`.a${i + 1}`, s, "snap"]),
      ],
      tweens: [
        ...p.steps
          .slice(1)
          .map((s, i) => [
            `.a${i + 1} path`,
            { strokeDashoffset: 1 },
            { strokeDashoffset: 0, duration: 0.5, ease: "power1.inOut" },
            s,
          ]),
        ...reveal(p.emphasis),
      ],
    };
  },
  panels: async (p, f, x) => {
    const n = p.items.length;
    const box = { w: Math.floor((1680 - (n - 1) * 40) / n), h: 560 };
    const shapes = await x.sketch(
      p.items.map((_, i) => ({ rect: [box.w, box.h], key: `panel${i}` })),
    );
    const em = emphasised(
      p.emphasis,
      p.items.map((it) => it.title),
    );
    return {
      html: `<div class="panels">${p.items
        .map(
          (it, i) =>
            `<div class="panel p${i}${host(i === em)}">${sketched(x.surface, { ...box, ...shapes[i] })}<div class="ptitle">${f.tt(it.title)}</div><div class="pbody">${f.t(it.body)}</div>${i === em ? callout() : ""}</div>`,
        )
        .join("")}</div>`,
      css: `.panels { position: absolute; inset: 0; display: flex; align-items: center; gap: 40px; }
.panel { ${boxCss(x.surface)} box-sizing: border-box; width: ${box.w}px; height: ${box.h}px; padding: 48px; text-align: start; }
.ptitle { position: relative; font: ${f.titleWeight} var(--size-title)/${f.lh(1.15, "title")} ${f.title}; color: var(--text); }
.pbody { position: relative; margin-top: 28px; font: 400 var(--size-body)/${f.lh(1.4, "text")} ${f.text}; color: var(--muted); }
${sketchCss(x.surface)}
${CALLOUT_CSS}`,
      reveals: p.items.map((it, i) => [`.p${i}`, it]),
      tweens: reveal(p.emphasis),
    };
  },
  list: (p, f) => {
    const em = emphasised(
      p.emphasis,
      p.items.map((it) => it.text),
    );
    return {
      html: `<div class="list">${p.title ? `<div class="ltitle lt">${f.tt(p.title)}</div>` : ""}${p.items
        .map(
          (it, i) =>
            `<div class="item i${i}${host(i === em, " row")}"><div class="dot"></div><div class="itext">${f.t(it.text)}</div>${i === em ? callout() : ""}</div>`,
        )
        .join("")}</div>`,
      css: `.list { position: absolute; inset: 0; display: flex; flex-direction: column; justify-content: center; gap: 26px; text-align: start; }
.ltitle { font: ${f.titleWeight} var(--size-title)/${f.lh(1.1, "title")} ${f.title}; color: var(--text); margin-bottom: 14px; }
.item { display: flex; align-items: center; gap: 28px; }
.dot { flex: 0 0 16px; height: 16px; border-radius: 4px; background: var(--accent); }
.itext { font: 400 var(--size-body)/${f.lh(1.3, "text")} ${f.text}; color: var(--text); }
${CALLOUT_CSS}`,
      reveals: [
        ...(p.title ? [[".lt", 1, "land"]] : []),
        ...p.items.map((it, i) => [`.i${i}`, it, "snap"]),
      ],
      tweens: reveal(p.emphasis),
    };
  },
  // Key lines, each a box of whole-word spans. A line read along (see
  // `readAlong`) rises word by word on each word's own spoken time and carries
  // `data-along` for the reading gate; any other rises on its cue, a stagger
  // apart. A Latin run glued into one span under right to left rises on the
  // last spoken word it holds.
  words: (p, f, x) => {
    const tweens = [];
    let next = 0;
    const lines = p.lines.map((line, i) => {
      const k = kineticWords(line.text, f, f.tt, next);
      const start = readAlong(x.said, line);
      let spoken = start;
      k.words.forEach((w, j) => {
        const blur = x.type.blur;
        tweens.push([
          `.k${next + j}`,
          {
            yPercent: WORD_RISE,
            opacity: 0,
            ...(blur && { filter: `blur(${blur}px)` }),
          },
          {
            yPercent: 0,
            opacity: 1,
            ...(blur && { filter: "blur(0px)" }),
            duration: WORD_RISE_SECONDS,
            ease: x.type.ease,
            ...(start < 0 && { delay: +(j * x.type.stagger).toFixed(6) }),
          },
          start < 0 ? line : { word: (spoken += w.split(" ").length) - 1 },
        ]);
      });
      next = k.count;
      return `<div class="kl" data-line="l${i}"${start < 0 ? "" : " data-along"}>${k.html}</div>`;
    });
    return {
      html: `<div class="klines">${lines.join("")}</div>`,
      css: `.klines { position: absolute; inset: 0; display: flex; flex-direction: column; justify-content: center; gap: 36px; }
.kl { font: ${f.titleWeight} var(--size-title)/${f.lh(1.15, "title")} ${f.title}; color: var(--text); letter-spacing: ${f.ls("-0.01em")}; max-width: 1680px; }
${WORD_CSS}`,
      reveals: [],
      tweens,
    };
  },
  code: async (p, f, x) => {
    const rows = await x.highlight(p.code, p.lang);
    const LH = x.row;
    // The ring spans the emphasised lines, as wide as the longest in `ch`, the
    // code face being monospace.
    const e = p.emphasis;
    const ring = e
      ? `<div class="em side" style="top: ${28 + (e.target[0] - 1) * LH - 4}px; height: ${(e.target[1] - e.target[0] + 1) * LH + 8}px; width: calc(${Math.max(
          ...lines(p.code)
            .slice(e.target[0] - 1, e.target[1])
            .map((l) => l.length),
        )}ch + 28px)"></div>`
      : "";
    const frame = codeFrame(
      p,
      f,
      ring + rows.map((row) => `<div class="ln">${tokens(row)}</div>`).join(""),
      LH,
      x.surface,
    );
    return {
      ...frame,
      css: `${frame.css}\n${CALLOUT_CSS}\n.body > .em { left: 30px; }`,
      reveals: [[".rt", 1]],
      tweens: reveal(e),
    };
  },
  // The diff plays at its sentence: removed lines close and added ones open,
  // their heights tweened, so the kept lines slide into place.
  codediff: async (p, f, x) => {
    const was = await x.highlight(p.before, p.lang);
    const now = await x.highlight(p.after, p.lang);
    const k = { del: 0, add: 0 };
    const shut = { height: 0, opacity: 0 };
    const LH = x.row;
    const open = { height: LH, opacity: 1 };
    const go = { duration: 0.5, ease: "power2.inOut" };
    const tweens = [];
    const rows = diff(lines(p.before), lines(p.after)).map(([op, i, j]) => {
      if (op === "keep") return `<div class="ln">${tokens(was[i])}</div>`;
      const cls = `${op}${k[op]++}`;
      tweens.push(
        op === "del"
          ? [`.${cls}`, open, { ...shut, ...go }, p]
          : [`.${cls}`, shut, { ...open, ...go }, p],
      );
      return `<div class="ln ${op} ${cls}">${tokens(op === "del" ? was[i] : now[j])}</div>`;
    });
    return {
      ...codeFrame(p, f, rows.join(""), LH, x.surface),
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
