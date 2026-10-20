// The HyperFrames composition in the profile's layout (`open` or `bands`), its
// ease `velocity`, `soft` or `spring` and its texture: a page per render (the
// video's index.html, or a stills page), and one sub-composition file per scene
// whose visual is a component. The palette, the type scale and the faces come
// from the style profile as CSS custom properties; every font is a file beside
// the page.
import { ARABIC, blursDepth, grammar, scale } from "../lib/style.mjs";
import { RISE_PX, SPRING, settleTime, step } from "../lib/spring.mjs";
import { splitLatin } from "../lib/terms.mjs";
import { cueWord } from "../lib/visuals.mjs";
import { COMPONENTS, ITEMS, esc, seed } from "./components.mjs";
import { texture } from "./texture.mjs";

export { esc };

export const W = 1920;
export const H = 1080;
export const FPS = 30;
// The content band every scene draws in, above the captions: under the `bands`
// layout's header, or from the top under `open`, which has none.
export const CONTENT = { left: 120, top: 178, width: 1680, height: 690 };
const OPEN = { left: 120, top: 96, width: 1680, height: 772 };
export const contentBox = (layout) => (layout === "open" ? OPEN : CONTENT);
// A caption is 40 px whatever the profile's `scale`: the caption band and
// CUE_CHARS are sized for it. 40 px Inter fits about 70 characters a line in
// the 1680 px band: 84 is at most two lines.
const CAPTION_PX = 40;
export const CUE_CHARS = 84;
const RISE = [
  { opacity: 0, y: RISE_PX },
  { opacity: 1, y: 0, duration: 0.35, ease: "power2.out" },
];
// A reveal under `velocity`: each class on its own fast-out ease, a headline
// the longest and a snap the sharpest.
const VELOCITY = {
  settle: { duration: 0.45, ease: "power3.out" },
  land: { duration: 0.6, ease: "power4.out" },
  snap: { duration: 0.3, ease: "expo.out" },
};
// A reveal under `spring`: the opacity, position and scale it starts from and
// ends on, the class's settle time as its duration, and the class itself, which
// the scene script evaluates (`SPRING[class]`) in place of a GSAP ease.
const sprung = (cls) => {
  const { scale } = SPRING[cls];
  const from = { opacity: 0, y: RISE_PX, ...(scale < 1 && { scale }) };
  const to = { opacity: 1, y: 0, ...(scale < 1 && { scale: 1 }) };
  return [from, { ...to, duration: settleTime(SPRING[cls]) }];
};

const family = (profile, role) => `"${profile.type[role].font}"`;
const weight = (profile, role) => profile.type[role].weight ?? 400;

// Right to left, the least line height a role's lines take: Arabic marks reach
// further above and below than Latin ones (the owner's pick, #686).
const AR_LH = { title: 1.5, text: 1.6, caption: 1.7 };

// The faces and text helpers a scene draws with. Right to left, titles and
// text take the Arabic roles, the Latin face behind each for a stray Latin
// glyph, and every Latin run (an English term, a number) is an isolated
// `<bdi>` set in the profile's Latin face and kept on one line.
export function faces(profile, dir = "ltr") {
  const rtl = dir === "rtl";
  const stack = (r) =>
    rtl
      ? `${family(profile, ARABIC[r])}, ${family(profile, r)}`
      : family(profile, r);
  const wrap = (cls) => (s) =>
    rtl
      ? splitLatin(String(s))
          .map((p, i) =>
            i % 2 ? `<bdi class="${cls}">${esc(p)}</bdi>` : esc(p),
          )
          .join("")
      : esc(s);
  return {
    rtl,
    text: stack("text"),
    title: stack("title"),
    titleWeight: weight(profile, rtl ? ARABIC.title : "title"),
    code: family(profile, "code"),
    // A card's or a flow step's note: the code face, which draws no Arabic.
    note: rtl ? stack("text") : family(profile, "code"),
    t: wrap("lat"),
    tt: wrap("lat ti"),
    lh: (v, role) => (rtl ? Math.max(v, AR_LH[role]) : v),
    // Spacing letters apart breaks the joins of Arabic script.
    ls: (v) => (rtl ? "0" : v),
  };
}

// A scene's sub-composition: its timeline reveals each piece as the sentence
// naming it starts, every tween on that paused timeline, so a frame renders the
// same whenever HyperFrames seeks to it. A stills page sets window.__stills, so
// the timeline jumps to its end and stays unregistered: HyperFrames never seeks
// it back. `dir` is the scene's reading direction; code stays left to right.
// `timing.slot`, longer than `timing.duration` by the scene's seam out, is the
// stretch the template runs for.
export async function sceneFile(scene, timing, profile, opts) {
  const { html, script } = await sceneParts(scene, timing, profile, opts);
  return `<template id="${scene.id}-template">
  <div data-composition-id="${scene.id}" data-width="${W}" data-height="${H}" data-duration="${timing.slot ?? timing.duration}">
${html}
    <script>
${script}
    </script>
  </div>
</template>
`;
}

// A scene's markup with its scoped style, and its timeline script, apart.
async function sceneParts(
  scene,
  timing,
  profile,
  { backend, dir = "ltr", seam = {} },
) {
  const id = scene.id;
  const f = faces(profile, dir);
  const { ease, layout, texture: tx } = grammar(profile);
  const { surface } = tx;
  const box = contentBox(layout);
  const x = {
    surface,
    // A code row is the code step at 1.4 (45 px at 32), so a `scale.code`
    // override keeps the text inside its row; 12 rows fit the band at the
    // default step only, a taller override is the layout gate's to catch.
    row: Math.round(scale(profile).code * 1.4),
    highlight: backend.highlight,
    sketch: async (shapes) =>
      surface === "sketch"
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
  // A cue is a sentence number, or `{ at, on }`: with `on`, the time of the
  // phrase's first voiced word.
  const t = (c) => {
    const cue = typeof c === "number" ? { at: c } : c;
    return cue.on === undefined
      ? timing.sentences[cue.at - 1]
      : timing.words[cueWord(scene.narration, cue)];
  };
  const reveal = ([sel, at, cls = "settle"]) => {
    if (ease === "spring") return [sel, ...sprung(cls), t(at), cls];
    const [from, to] =
      ease === "velocity" ? [RISE[0], { ...RISE[1], ...VELOCITY[cls] }] : RISE;
    return [sel, from, to, t(at)];
  };
  // Depth: once the emphasis lands, every item but the emphasised one falls out
  // of focus.
  const emphasis = scene.visual.props.emphasis;
  const depth =
    emphasis && blursDepth(tx, scene.visual.component)
      ? [
          [
            `:is(${ITEMS}):not(.em-host)`,
            { filter: "blur(0px)" },
            { filter: `blur(${tx.depthBlur}px)`, duration: 0.35 },
            t(emphasis),
          ],
        ]
      : [];
  const tweens = [
    ...c.reveals.map(reveal),
    ...(c.tweens ?? []).map(([sel, from, to, at]) => [sel, from, to, t(at)]),
    ...depth,
  ];
  return {
    html: `    <div class="content" dir="${dir}">${c.html}</div>
    <style>
${scope} .content { position: absolute; left: ${box.left}px; top: ${box.top}px; width: ${box.width}px; height: ${box.height}px; }
${css}
    </style>`,
    script: `      (function () {
        const tl = gsap.timeline({ paused: true });
        const tweens = ${JSON.stringify(tweens)};
${play(scope, tweens)}${seamScript(scope, seam, timing.duration, dir === "rtl")}
        window.__timelines = window.__timelines || {};
        if (window.__stills) tl.progress(1);
        else window.__timelines["${id}"] = tl;
      })();`,
  };
}

// A seam's two halves on a scene's `.content`, as `[from, to]` tween vars: the
// exit of the outgoing scene, the entry of the incoming one. Blur is left off
// at 0: a filter of any value, even `blur(0px)`, makes the content a backdrop
// root that the glass surface cannot see through.
const blur = (px) => ({ filter: `blur(${px}px)` });
const SEAMS = {
  // Through the frame: the exit grows to 1.2 and blurs, the entry settles in
  // from 0.75.
  "zoom-through": {
    exit: (b, d) => [
      { scale: 1, opacity: 1, ...(b && blur(0)) },
      {
        scale: 1.2,
        opacity: 0,
        ...(b && blur(b)),
        duration: d,
        ease: "power3.in",
      },
    ],
    entry: (b, d) => [
      { scale: 0.75, opacity: 0, ...(b && blur(b)) },
      {
        scale: 1,
        opacity: 1,
        ...(b && blur(0)),
        duration: d,
        ease: "expo.out",
      },
    ],
  },
  // Along the reading direction: `s` is 1 left to right, -1 right to left.
  "cut-the-curve": {
    exit: (b, d, s) => [
      { xPercent: 0, opacity: 1, ...(b && blur(0)) },
      {
        xPercent: -13 * s,
        opacity: 0,
        ...(b && blur(b)),
        duration: d,
        ease: "power2.in",
      },
    ],
    entry: (b, d, s) => [
      { xPercent: 13 * s, opacity: 0, ...(b && blur(b)) },
      {
        xPercent: 0,
        opacity: 1,
        ...(b && blur(0)),
        duration: d,
        ease: "power4.out",
      },
    ],
  },
};

// The script lines that play a scene's seam: its entry over the first
// `seam.in.duration` seconds, its exit from `end`, the scene's own last
// moment, on into the next scene's start. The `seam:start`/`seam:end` labels
// (`seam:start2`/`seam:end2` for the exit when both run) mark the windows for
// the gates. A stills page runs no seam: it holds each scene settled at its
// end.
function seamScript(scope, seam, end, rtl) {
  const halves = [
    ["entry", seam.in, 0],
    ["exit", seam.out, end],
  ].filter(([, x]) => x);
  if (!halves.length) return "";
  const lines = halves.map(([half, x, at], k) => {
    const [from, to] = SEAMS[x.move][half](x.blur, x.duration, rtl ? -1 : 1);
    // The entry hides the scene from its first frame and clears what it set,
    // the exit leaves the scene whole until it runs and ends it gone.
    const vars =
      half === "entry"
        ? { ...to, clearProps: "all" }
        : { ...to, immediateRender: false };
    const n = k ? k + 1 : "";
    return `          tl.fromTo('${scope} .content', ${JSON.stringify(from)}, ${JSON.stringify(vars)}, ${at});
          tl.addLabel("seam:start${n}", ${at}).addLabel("seam:end${n}", ${+(at + x.duration).toFixed(6)});`;
  });
  return `
        if (!window.__stills) {
${lines.join("\n")}
        }`;
}

// The script lines that play a scene's tweens on its timeline. A tween naming a
// spring class evaluates `SPRING[class]` (written into the script with the
// functions that read it) in place of a GSAP ease: opacity rises on its own
// ease, never past 1, and position and scale follow the spring.
const play = (scope, tweens) =>
  tweens.some((x) => x[4])
    ? `        const SPRING = ${JSON.stringify(SPRING)};
        ${settleTime}
        ${step}
        for (const [sel, from, to, t, cls] of tweens) {
          if (!cls) {
            tl.fromTo('${scope} ' + sel, from, to, t);
            continue;
          }
          const { opacity: o0, ...move } = from;
          const { opacity: o1, duration, ...end } = to;
          tl.fromTo('${scope} ' + sel, { opacity: o0 }, { opacity: o1, duration: ${RISE[1].duration}, ease: "${RISE[1].ease}" }, t);
          tl.fromTo('${scope} ' + sel, move, { ...end, duration, ease: (p) => p >= 1 ? 1 : step(SPRING[cls], p * duration) }, t);
        }`
    : `        for (const [sel, from, to, t] of tweens)
          tl.fromTo('${scope} ' + sel, from, to, t);`;

// A full page: fonts, palette, the texture behind and over `body` and, under
// `bands`, the header band, inside the root. Right to left, the header and the
// captions mirror and the root does not: `dir` sits on the text boxes alone.
function page({
  title,
  profile,
  fonts,
  duration,
  head = "",
  body,
  script,
  dir = "ltr",
}) {
  const fontFaces = fonts
    .map(
      (x) =>
        `@font-face { font-family: "${x.family}"; src: url("fonts/${x.file}"); font-weight: ${x.weight}; font-style: ${x.style}; font-display: block; }`,
    )
    .join("\n");
  const f = faces(profile, dir);
  const { layout, texture: tx } = grammar(profile);
  const tex = texture(tx);
  const bands = layout === "bands";
  const tokens = [
    ...Object.entries(profile.colors).map(([k, v]) => `--${k}: ${v};`),
    ...Object.entries({ ...scale(profile), caption: CAPTION_PX }).map(
      ([k, v]) => `--size-${k}: ${v}px;`,
    ),
    `--font-title: ${f.title};`,
    `--font-text: ${f.text};`,
    `--font-code: ${f.code};`,
  ].join(" ");
  // Arabic captions: 40 px at 1.7, two lines (136 px) between the content box
  // (y 868, plus 12 px clear) and the 5 percent safe margin (y 1026).
  const band = f.rtl
    ? "top: 880px; height: 136px;"
    : "top: 908px; height: 104px;";
  const latin = f.rtl
    ? `\n.lat { font-family: ${family(profile, "text")}; white-space: nowrap; }
.lat.ti { font-family: ${family(profile, "title")}; }`
    : "";
  return `<!doctype html>
<html lang="${f.rtl ? "ar" : "en"}">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=${W}, height=${H}" />
    <title>${esc(title)}</title>
${head}    <script src="gsap.min.js"></script>
    <style>
${fontFaces}
:root { ${tokens} }
html, body { margin: 0; width: ${W}px; height: ${H}px; overflow: hidden; background: var(--bg); }
#root { position: relative; width: ${W}px; height: ${H}px; overflow: hidden; background: var(--bg); color: var(--text); font-family: ${f.text}; }
.clip { position: absolute; inset: 0; }${
    bands
      ? `
.header { position: absolute; left: 120px; right: 120px; top: 56px; height: 80px; display: flex; align-items: center; gap: 22px; border-bottom: 1px solid var(--line); }
.mark { width: 18px; height: 18px; border-radius: 4px; background: var(--accent); }
.kicker { font: 600 var(--size-label) ${f.text}; color: var(--muted); letter-spacing: ${f.ls("0.04em")}; text-transform: uppercase; }`
      : ""
  }
${tex.css}
.captions { position: absolute; z-index: 30; left: 120px; right: 120px; ${band} }
.cue { display: flex; align-items: center; justify-content: center; text-align: center; font: 400 var(--size-caption)/${f.lh(1.3, "caption")} ${f.text}; color: var(--faint); overflow: hidden; }${latin}
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-width="${W}" data-height="${H}" data-fps="${FPS}" data-duration="${duration}">
${tex.back}${bands ? `      <div class="header" dir="${dir}"><div class="mark"></div><div class="kicker">${f.t(title)}</div></div>\n` : ""}${body}
${tex.front}    </div>
    <script>
${script}
    </script>
  </body>
</html>
`;
}

// The video: every scene mounted at its start for its duration, the caption
// cues on the root timeline, each word turning the text colour as it is said.
export function videoPage({
  title,
  profile,
  fonts,
  scenes,
  cues,
  total,
  dir = "ltr",
}) {
  const f = faces(profile, dir);
  // A scene is mounted for its slot: it runs on past its own duration into its
  // seam, over the next scene's start; clips on one track may overlap, the
  // later one layering above (measured: a real render of that overlap passes).
  const hosts = scenes
    .map(
      (s) =>
        `      <div id="scene-${s.id}" class="clip" data-composition-id="${s.id}" data-composition-src="scenes/${s.id}.html" data-start="${s.start}" data-duration="${s.slot ?? s.duration}" data-track-index="1"></div>`,
    )
    .join("\n");
  const captions = cues
    .map(
      (c, i) =>
        `<div class="cue clip" data-start="${c.start}" data-duration="${+(c.end - c.start).toFixed(3)}" data-track-index="2" id="cue-${i + 1}" dir="${dir}"><span>${c.tokens
          .map(
            (t) => `<span class="w" data-at="${t.start}">${f.t(t.text)}</span>`,
          )
          .join(" ")}</span></div>`,
    )
    .join("\n        ");
  return page({
    title,
    profile,
    fonts,
    dir,
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

// A caption cue held still with its first half said: those words in the text
// colour, the rest faint. Right to left, a Latin run is one word, so a
// multi-word term keeps its order.
function stillCue(text, attrs, f) {
  const words = f.rtl
    ? splitLatin(text).flatMap((p, i) =>
        i % 2 ? [p] : p.split(/\s+/).filter(Boolean),
      )
    : text.split(/\s+/);
  const said = Math.ceil(words.length / 2);
  return `<div class="cue clip"${attrs}${f.rtl ? ' dir="rtl"' : ""}><span>${words
    .map(
      (w, i) =>
        `<span class="w"${i < said ? ' style="color: var(--text)"' : ""}>${f.t(w)}</span>`,
    )
    .join(" ")}</span></div>`;
}

// One frame per scene, each scene settled at its end; `cues` holds a still
// caption for a scene by its id, and `frame` is each scene's stretch in
// seconds. data-no-timeline stops HyperFrames waiting for the timelines the
// scenes leave unregistered.
export function stillsPage({
  title,
  profile,
  fonts,
  ids,
  cues = {},
  frame = 1 / FPS,
  dir = "ltr",
}) {
  const f = faces(profile, dir);
  const at = (i) =>
    ` data-start="${+(i * frame).toFixed(6)}" data-duration="${+frame.toFixed(6)}"`;
  const held = ids.filter((id) => cues[id]);
  return page({
    title,
    profile,
    fonts,
    dir,
    duration: +(ids.length * frame).toFixed(6),
    head: "    <script>window.__stills = true;</script>\n",
    body:
      ids
        .map(
          (id, i) =>
            `      <div id="scene-${id}" class="clip" data-composition-id="${id}" data-composition-src="scenes/${id}.html"${at(i)} data-track-index="1" data-no-timeline></div>`,
        )
        .join("\n") +
      (held.length
        ? `\n      <div class="captions">${held
            .map((id) =>
              stillCue(
                cues[id],
                `${at(ids.indexOf(id))} data-track-index="2" id="cue-${id}"`,
                f,
              ),
            )
            .join("")}</div>`
        : ""),
    script: `      window.__timelines = window.__timelines || {};
      window.__timelines["main"] = gsap.timeline({ paused: true });`,
  });
}

// One settled scene as a static page with no script of its own, its markup
// inline and an optional still caption: the style card shows it in a frame
// that runs no script.
export async function framePage({
  title,
  profile,
  fonts,
  scene,
  cue,
  ...opts
}) {
  const { html } = await sceneParts(
    scene,
    { duration: 1, sentences: [] },
    profile,
    opts,
  );
  const dir = opts.dir ?? "ltr";
  return page({
    title,
    profile,
    fonts,
    dir,
    duration: 1,
    body: `      <div class="clip" data-composition-id="${scene.id}">
${html}
      </div>${cue ? `\n      <div class="captions">${stillCue(cue, "", faces(profile, dir))}</div>` : ""}`,
    script: "",
  });
}
