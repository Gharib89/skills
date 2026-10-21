// The HyperFrames composition in the profile's layout (`open` or `bands`), its
// ease `velocity`, `soft` or `spring` and its texture: a page per render (the
// video's index.html, or a stills page), and one sub-composition file per scene
// whose visual is a component. The palette, the type scale and the faces come
// from the style profile as CSS custom properties; every font is a file beside
// the page.
import { COUNT_SECONDS } from "../lib/count.mjs";
import { ARABIC, blursDepth, grammar, scale } from "../lib/style.mjs";
import { RISE_PX, SPRING, settleTime } from "../lib/spring.mjs";
import { splitLatin } from "../lib/terms.mjs";
import { VISUALS, cameraCue, cueWord } from "../lib/visuals.mjs";
import { COMPONENTS, ITEMS, esc, seed } from "./components.mjs";
import { fragmentScript } from "./fragment-script.mjs";
import { pushScript, seamScript } from "./seam-script.mjs";
import { texture } from "./texture.mjs";
import { RISE, countScript, play } from "./tween-script.mjs";

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
// The blur in px a title's words resolve out of under the type family `words`.
const TITLE_BLUR = 12;
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
// the timeline jumps to the scene's fullest moment, every reveal landed and the
// exit not begun, and stays unregistered: HyperFrames never seeks it back. `dir` is the scene's reading direction; code stays left to right.
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
  const { bans, camera, ease, layout, texture: tx, type } = grammar(profile);
  const { surface } = tx;
  const pushes =
    camera.family === "push" &&
    !bans.includes("camera") &&
    !VISUALS[scene.visual.component].ownCamera;
  const box = contentBox(layout);
  // A cue is a sentence number, or `{ at, on }`: with `on`, the time of the
  // phrase's first voiced word. `{ word }` is the scene's nth voiced word.
  const t = (c) => {
    const cue = typeof c === "number" ? { at: c } : c;
    if (cue.word !== undefined) return timing.words[cue.word];
    return cue.on === undefined
      ? timing.sentences[cue.at - 1]
      : timing.words[cueWord(scene.narration, cue)];
  };
  const x = {
    surface,
    // A cue's time in seconds, and the scene's end, for a component whose
    // tweens depend on the gap between two cues or on the time left.
    time: t,
    end: timing.duration,
    // The content box, for a component the composer lays out itself.
    box,
    // The scene's selector scope and the seconds its template runs (its slot),
    // for a component whose own script draws on the paused timeline `tl`.
    scope: `[data-composition-id="${id}"]`,
    slot: timing.slot ?? timing.duration,
    // A code row is the code step at 1.4 (45 px at 32), so a `scale.code`
    // override keeps the text inside its row; 12 rows fit the band at the
    // default step only, a taller override is the layout gate's to catch.
    row: Math.round(scale(profile).code * 1.4),
    // The type family, and the blur in px a title resolves out of (none under
    // a `blur` ban).
    type: {
      words: type.family === "words",
      stagger: type.stagger,
      // `soft` is one `power2` ease for every reveal; a word's rise is a
      // `power4` headline's under the other families, since a spring has no
      // per-word form.
      ease: ease === "soft" ? "power2.out" : "power4.out",
      blur: bans.includes("blur") ? 0 : TITLE_BLUR,
    },
    // The scene's sentences in spoken form, for a cue that lands on words.
    said: scene.narration,
    highlight: backend.highlight,
    sketch: async (shapes) =>
      surface === "sketch"
        ? backend.sketch(
            shapes.map(({ key, ...s }) => ({ ...s, seed: seed(id, key) })),
          )
        : [],
  };
  const c = await COMPONENTS[scene.visual.component](scene.visual.props, f, x);
  const scope = x.scope;
  const css = c.css
    .split("\n")
    .filter((l) => l.trim())
    .map((l) => `${scope} ${l}`)
    .join("\n");
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
  // The push-in lands on its cue, or runs from the scene's start when the cue
  // falls under one push duration in.
  const push = pushes
    ? +Math.max(
        0,
        t(cameraCue(scene.visual, scene.narration)) - camera.duration,
      ).toFixed(6)
    : null;
  // A number counts up within the scene: a cue near the end shortens its count
  // (and its bar) rather than cutting away on a half-counted number.
  const fit = (at, d) =>
    c.counts
      ? +Math.min(d, Math.max(timing.duration - at, 0.05)).toFixed(6)
      : d;
  // A tween repeating forever (`repeat: -1`) repeats until it has reached the
  // scene's end, and no further: the timeline stays finite, so a frame is a
  // function of its time. One starting at or past the end keeps a single run,
  // its from state drawn, and the page's timeline stops at the end.
  const repeats = (to, at) =>
    to.repeat === -1
      ? {
          ...to,
          repeat: Math.max(
            0,
            Math.ceil((timing.duration - at - (to.delay ?? 0)) / to.duration) -
              1,
          ),
        }
      : to;
  const tweens = [
    ...c.reveals.map(reveal),
    ...(c.tweens ?? []).map(([sel, from, to, at]) => [
      sel,
      from,
      repeats(
        to.duration ? { ...to, duration: fit(t(at), to.duration) } : to,
        t(at),
      ),
      t(at),
    ]),
    ...depth,
  ];
  const counts = (c.counts ?? []).map(([sel, written, at]) => [
    sel,
    written,
    t(at),
    fit(t(at), COUNT_SECONDS),
  ]);
  // A custom scene's declared cues, each resolved to its time in seconds.
  const fragment = c.fragment
    ? fragmentScript(
        scope,
        c.fragment.script,
        Object.fromEntries(
          c.fragment.cues.map(({ name, ...cue }) => [name, t(cue)]),
        ),
        timing.duration,
      )
    : "";
  return {
    html: `    <div class="content" dir="${dir}">${push === null ? c.html : `<div class="camera">${c.html}</div>`}</div>
    <style>
${scope} .content { position: absolute; left: ${box.left}px; top: ${box.top}px; width: ${box.width}px; height: ${box.height}px; }${push === null ? "" : `\n${scope} .camera { width: 100%; height: 100%; }`}
${css}
    </style>`,
    script: `      (function () {
        const tl = gsap.timeline({ paused: true });
        const tweens = ${JSON.stringify(tweens)};
${play(scope, tweens)}${countScript(scope, counts)}${fragment}${pushScript(scope, push, camera)}${c.script ? `\n${c.script}` : ""}
        // never before the entry seam ends: earlier the content is still fading in
        const full = Math.min(Math.max(tl.duration(), ${seam.in?.duration ?? 0}), ${timing.duration});${seamScript(scope, seam, timing.duration, dir === "rtl")}
        window.__timelines = window.__timelines || {};
        if (window.__stills) tl.time(full);
        else window.__timelines["${id}"] = tl;
      })();`,
  };
}

// A full page: fonts, palette, the texture behind and over `body` and, under
// `bands`, the header band, inside the root. Right to left, the header and the
// captions mirror and the root does not: `dir` sits on the text boxes alone.
function page({
  title,
  profile,
  fonts,
  duration,
  head = "",
  three = false,
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
${head}    <script src="gsap.min.js"></script>${three ? '\n    <script src="three.min.js"></script>' : ""}
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
  webgl = false,
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
    three: webgl,
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

// One frame per scene, each scene at its fullest moment; `cues` holds a still
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
  webgl = false,
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
    three: webgl,
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
