// The HyperFrames composition in the `bands` layout with `rise` motion: a page
// per render (the video's index.html, or a stills page), and one sub-composition
// file per scene whose visual is a component. The palette comes from the style
// profile as CSS custom properties; every font is a file beside the page.
import crypto from "node:crypto";

export const W = 1920;
export const H = 1080;
export const FPS = 30;
// 40 px Inter fits about 70 characters a line in the 1680 px band: 84 is at
// most two lines.
export const CUE_CHARS = 84;
const RISE = [
  { opacity: 0, y: 20 },
  { opacity: 1, y: 0, duration: 0.35, ease: "power2.out" },
];
// A code line's height: 30 px at 1.5.
const LH = 45;

export const esc = (s) =>
  String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

const family = (profile, role) => `"${profile.type[role].font}"`;
const weight = (profile, role) => profile.type[role].weight ?? 400;

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

// The lines of `a` and `b` as keep, del and add rows, the longest common
// subsequence kept.
function diff(a, b) {
  const L = Array.from({ length: a.length + 1 }, () =>
    new Array(b.length + 1).fill(0),
  );
  for (let i = a.length - 1; i >= 0; i--)
    for (let j = b.length - 1; j >= 0; j--)
      L[i][j] =
        a[i] === b[j]
          ? L[i + 1][j + 1] + 1
          : Math.max(L[i + 1][j], L[i][j + 1]);
  const out = [];
  let i = 0;
  let j = 0;
  while (i < a.length || j < b.length)
    if (i < a.length && j < b.length && a[i] === b[j])
      out.push(["keep", i++, j++]);
    else if (j < b.length && (i === a.length || L[i][j + 1] >= L[i + 1][j]))
      out.push(["add", i, j++]);
    else out.push(["del", i++, j]);
  return out;
}

// Each component: its markup, its scoped CSS, what reveals when, as [selector,
// sentence number] pairs, and its other tweens, as [selector, from, to,
// sentence number]. `x` holds the profile's look and allowed effects, Shiki's
// tokens and rough.js outlines.
const COMPONENTS = {
  title: (p, f) => ({
    html: `<div class="stack">${p.kicker ? `<div class="kick r0">${esc(p.kicker)}</div>` : ""}<div class="big r0">${esc(p.title)}</div>${p.subtitle ? `<div class="sub r0">${esc(p.subtitle)}</div>` : ""}</div>`,
    css: `.stack { position: absolute; inset: 0; display: flex; flex-direction: column; justify-content: center; gap: 28px; }
.kick { font: 600 30px ${f.text}; color: var(--accent); letter-spacing: 0.06em; text-transform: uppercase; }
.big { font: ${f.titleWeight} 112px/1.08 ${f.title}; color: var(--text); letter-spacing: -0.01em; max-width: 1600px; }
.sub { font: 400 40px/1.3 ${f.text}; color: var(--muted); max-width: 1500px; }`,
    reveals: [[".r0", 1]],
  }),
  cards: (p, f) => ({
    html: `<div class="rail">${p.items
      .map(
        (x, i) =>
          `<div class="card r${i}"><div class="label">${esc(x.label)}</div><div class="value">${esc(x.value)}</div>${x.note ? `<div class="note">${esc(x.note)}</div>` : ""}</div>`,
      )
      .join("")}</div>`,
    css: `.rail { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; gap: 40px; }
.card { flex: 0 1 380px; min-height: 240px; box-sizing: border-box; background: var(--panel); border: 2px solid var(--line); border-radius: 18px; padding: 34px; }
.label { font: 600 24px ${f.text}; color: var(--muted); letter-spacing: 0.06em; text-transform: uppercase; }
.value { margin-top: 26px; font: ${f.titleWeight} 54px/1.1 ${f.title}; color: var(--text); }
.note { margin-top: 22px; font: 400 28px ${f.code}; color: var(--muted); }`,
    reveals: p.items.map((x, i) => [`.r${i}`, x.at]),
  }),
  terminal: (p, f) => ({
    html: `<div class="term rt"><div class="bar"><div class="dot"></div><div class="dot"></div><div class="dot"></div>${p.title ? `<span class="name">${esc(p.title)}</span>` : ""}</div><div class="body">${p.lines
      .map((x, i) => `<div class="line r${i}">${esc(x.text)}</div>`)
      .join("")}</div></div>`,
    css: `.term { position: absolute; left: 260px; top: 30px; width: 1240px; height: 600px; box-sizing: border-box; background: var(--panel); border: 2px solid var(--line); border-radius: 18px; overflow: hidden; }
.bar { height: 56px; border-bottom: 1px solid var(--line); display: flex; align-items: center; padding: 0 26px; gap: 12px; font: 400 24px ${f.code}; color: var(--muted); }
.dot { width: 14px; height: 14px; border-radius: 50%; background: var(--line); }
.name { margin-left: 16px; }
.body { padding: 34px 44px; font: 400 34px/1.7 ${f.code}; color: var(--text); }
.line { white-space: pre; }`,
    reveals: [[".rt", 1], ...p.lines.map((x, i) => [`.r${i}`, x.at])],
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
            `${i ? arrow(i) : ""}<div class="node n${i}">${sketched(x.look, { ...box, ...shapes[i] })}<div class="label">${esc(s.label)}</div>${s.note ? `<div class="note">${esc(s.note)}</div>` : ""}</div>`,
        )
        .join("")}</div>`,
      css: `.flow { position: absolute; inset: 0; display: flex; align-items: center; }
.node { ${boxCss(x.look)} box-sizing: border-box; width: ${box.w}px; height: ${box.h}px; padding: 28px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px; text-align: center; }
.label { position: relative; font: ${f.titleWeight} 46px/1.1 ${f.title}; color: var(--text); }
.note { position: relative; font: 400 26px ${f.code}; color: var(--muted); }
.arrow { flex: 0 0 ${gap}px; display: flex; justify-content: center; }
.arrow path { fill: none; stroke: var(--rule); stroke-width: 4; stroke-linecap: round; stroke-linejoin: round; }
[dir="rtl"] .arrow svg { transform: scaleX(-1); }
${sketchCss(x.look)}`,
      reveals: [
        ...p.steps.map((s, i) => [`.n${i}`, s.at]),
        ...p.steps.slice(1).map((s, i) => [`.a${i + 1}`, s.at]),
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
            `<div class="panel p${i}">${sketched(x.look, { ...box, ...shapes[i] })}<div class="ptitle">${esc(it.title)}</div><div class="pbody">${esc(it.body)}</div></div>`,
        )
        .join("")}</div>`,
      css: `.panels { position: absolute; inset: 0; display: flex; align-items: center; gap: 40px; }
.panel { ${boxCss(x.look)} box-sizing: border-box; width: ${box.w}px; height: ${box.h}px; padding: 48px; text-align: start; }
.ptitle { position: relative; font: ${f.titleWeight} 52px/1.15 ${f.title}; color: var(--text); }
.pbody { position: relative; margin-top: 28px; font: 400 36px/1.4 ${f.text}; color: var(--muted); }
${sketchCss(x.look)}`,
      reveals: p.items.map((it, i) => [`.p${i}`, it.at]),
    };
  },
  list: (p, f) => ({
    html: `<div class="list">${p.title ? `<div class="ltitle lt">${esc(p.title)}</div>` : ""}${p.items
      .map(
        (it, i) =>
          `<div class="item i${i}"><div class="dot"></div><div class="itext">${esc(it.text)}</div></div>`,
      )
      .join("")}</div>`,
    css: `.list { position: absolute; inset: 0; display: flex; flex-direction: column; justify-content: center; gap: 26px; text-align: start; }
.ltitle { font: ${f.titleWeight} 60px/1.1 ${f.title}; color: var(--text); margin-bottom: 14px; }
.item { display: flex; align-items: center; gap: 28px; }
.dot { flex: 0 0 16px; height: 16px; border-radius: 4px; background: var(--accent); }
.itext { font: 400 42px/1.3 ${f.text}; color: var(--text); }`,
    reveals: [
      ...(p.title ? [[".lt", 1]] : []),
      ...p.items.map((it, i) => [`.i${i}`, it.at]),
    ],
  }),
  code: async (p, f, x) => {
    const lines = await x.highlight(p.code, p.lang);
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
        bars + lines.map((l) => `<div class="ln">${tokens(l)}</div>`).join(""),
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
    const rows = diff(p.before.split("\n"), p.after.split("\n")).map(
      ([op, i, j]) => {
        if (op === "keep") return `<div class="ln">${tokens(was[i])}</div>`;
        const cls = `${op}${k[op]++}`;
        tweens.push(
          op === "del"
            ? [`.${cls}`, open, { ...shut, ...go }, p.at]
            : [`.${cls}`, shut, { ...open, ...go }, p.at],
        );
        return `<div class="ln ${op} ${cls}">${tokens(op === "del" ? was[i] : now[j])}</div>`;
      },
    );
    return {
      ...codeFrame(p, f, rows.join("")),
      reveals: [[".rt", 1]],
      tweens,
    };
  },
};

// A rough.js seed per element, from its scene and its key, so a render repeats
// exactly and an edit to one scene never moves another's strokes.
const seed = (id, key) =>
  parseInt(
    crypto
      .createHash("sha256")
      .update(`${id}:${key}`)
      .digest("hex")
      .slice(0, 8),
    16,
  ) || 1;

// A scene's sub-composition: its timeline reveals each piece as the sentence
// naming it starts, every tween on that paused timeline, so a frame renders the
// same whenever HyperFrames seeks to it. A stills page sets window.__stills, so
// the timeline jumps to its end and stays unregistered: HyperFrames never seeks
// it back. `dir` is the scene's reading direction; code stays left to right.
export async function sceneFile(
  scene,
  timing,
  profile,
  { backend, dir = "ltr" },
) {
  const id = scene.id;
  const f = {
    text: family(profile, "text"),
    title: family(profile, "title"),
    titleWeight: weight(profile, "title"),
    code: family(profile, "code"),
  };
  const look = profile.look ?? "clean";
  const x = {
    look,
    effects: new Set(profile.effects ?? []),
    highlight: (code, lang) => backend.highlight(code, lang),
    sketch: async (shapes) =>
      look === "sketch"
        ? backend.sketch(
            shapes.map(({ key, ...s }) => ({ ...s, seed: seed(id, key) })),
          )
        : [],
  };
  const c = await COMPONENTS[scene.visual.component](scene.visual.props, f, x);
  const scope = `[data-composition-id="${id}"]`;
  const css = c.css
    .split("\n")
    .filter((l) => l.trim())
    .map((l) => `${scope} ${l}`)
    .join("\n");
  const t = (at) => timing.sentences[at - 1];
  const tweens = [
    ...c.reveals.map(([sel, at]) => [sel, ...RISE, t(at)]),
    ...(c.tweens ?? []).map(([sel, from, to, at]) => [sel, from, to, t(at)]),
  ];
  return `<template id="${id}-template">
  <div data-composition-id="${id}" data-width="${W}" data-height="${H}" data-duration="${timing.duration}">
    <div class="content" dir="${dir}">${c.html}</div>
    <style>
${scope} .content { position: absolute; left: 120px; top: 178px; width: 1680px; height: 690px; }
${css}
    </style>
    <script>
      (function () {
        const tl = gsap.timeline({ paused: true });
        const tweens = ${JSON.stringify(tweens)};
        for (const [sel, from, to, t] of tweens)
          tl.fromTo('${scope} ' + sel, from, to, t);
        window.__timelines = window.__timelines || {};
        if (window.__stills) tl.progress(1);
        else window.__timelines["${id}"] = tl;
      })();
    </script>
  </div>
</template>
`;
}

// A full page: fonts, palette, the header band, then `body` inside the root.
function page({ title, profile, fonts, duration, head = "", body, script }) {
  const faces = fonts
    .map(
      (x) =>
        `@font-face { font-family: "${x.family}"; src: url("fonts/${x.file}"); font-weight: ${x.weight}; font-style: ${x.style}; font-display: block; }`,
    )
    .join("\n");
  const palette = Object.entries(profile.colors)
    .map(([k, v]) => `--${k}: ${v};`)
    .join(" ");
  const text = family(profile, "text");
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=${W}, height=${H}" />
    <title>${esc(title)}</title>
${head}    <script src="gsap.min.js"></script>
    <style>
${faces}
:root { ${palette} }
html, body { margin: 0; width: ${W}px; height: ${H}px; overflow: hidden; background: var(--bg); }
#root { position: relative; width: ${W}px; height: ${H}px; overflow: hidden; background: var(--bg); color: var(--text); font-family: ${text}; }
.clip { position: absolute; inset: 0; }
.header { position: absolute; left: 120px; right: 120px; top: 56px; height: 80px; display: flex; align-items: center; gap: 22px; border-bottom: 1px solid var(--line); }
.mark { width: 18px; height: 18px; border-radius: 4px; background: var(--accent); }
.kicker { font: 600 26px ${text}; color: var(--muted); letter-spacing: 0.04em; text-transform: uppercase; }
.captions { position: absolute; left: 120px; right: 120px; top: 908px; height: 104px; }
.cue { display: flex; align-items: center; justify-content: center; text-align: center; font: 400 40px/1.3 ${text}; color: var(--faint); overflow: hidden; }
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-width="${W}" data-height="${H}" data-fps="${FPS}" data-duration="${duration}">
      <div class="header"><div class="mark"></div><div class="kicker">${esc(title)}</div></div>
${body}
    </div>
    <script>
${script}
    </script>
  </body>
</html>
`;
}

// The video: every scene mounted at its start for its duration, the caption
// cues on the root timeline, each word turning the text colour as it is said.
export function videoPage({ title, profile, fonts, scenes, cues, total }) {
  const hosts = scenes
    .map(
      (s) =>
        `      <div id="scene-${s.id}" class="clip" data-composition-id="${s.id}" data-composition-src="scenes/${s.id}.html" data-start="${s.start}" data-duration="${s.duration}" data-track-index="1"></div>`,
    )
    .join("\n");
  const captions = cues
    .map(
      (c, i) =>
        `<div class="cue clip" data-start="${c.start}" data-duration="${+(c.end - c.start).toFixed(3)}" data-track-index="2" id="cue-${i + 1}"><span>${c.tokens
          .map(
            (t) => `<span class="w" data-at="${t.start}">${esc(t.text)}</span>`,
          )
          .join(" ")}</span></div>`,
    )
    .join("\n        ");
  return page({
    title,
    profile,
    fonts,
    duration: total,
    body: `${hosts}
      <div class="captions">
        ${captions}
      </div>
      <audio id="narration" src="narration.wav" data-start="0" data-duration="${total}" data-track-index="3" data-volume="1"></audio>`,
    script: `      (function () {
        const tl = gsap.timeline({ paused: true });
        document.querySelectorAll("#root .cue .w").forEach((w) =>
          tl.set(w, { color: "${profile.colors.text}" }, +w.dataset.at),
        );
        window.__timelines = window.__timelines || {};
        window.__timelines["main"] = tl;
      })();`,
  });
}

// One frame per scene, each scene settled at its end. data-no-timeline stops
// HyperFrames waiting for the timelines the scenes leave unregistered.
export function stillsPage({ title, profile, fonts, ids }) {
  const frame = 1 / FPS;
  return page({
    title,
    profile,
    fonts,
    duration: +(ids.length * frame).toFixed(6),
    head: "    <script>window.__stills = true;</script>\n",
    body: ids
      .map(
        (id, i) =>
          `      <div id="scene-${id}" class="clip" data-composition-id="${id}" data-composition-src="scenes/${id}.html" data-start="${+(i * frame).toFixed(6)}" data-duration="${+frame.toFixed(6)}" data-track-index="1" data-no-timeline></div>`,
      )
      .join("\n"),
    script: `      window.__timelines = window.__timelines || {};
      window.__timelines["main"] = gsap.timeline({ paused: true });`,
  });
}
