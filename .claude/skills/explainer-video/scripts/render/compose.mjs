// The HyperFrames composition in the `bands` layout with `rise` motion: a page
// per render (the video's index.html, or a stills page), and one sub-composition
// file per scene whose visual is a component. The palette comes from the style
// profile as CSS custom properties; every font is a file beside the page.
export const W = 1920;
export const H = 1080;
export const FPS = 30;
const RISE = '{ opacity: 1, y: 0, duration: 0.35, ease: "power2.out" }';

export const esc = (s) =>
  String(s)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

const family = (profile, role) => `"${profile.type[role].font}"`;
const weight = (profile, role) => profile.type[role].weight ?? 400;

// Each component: its markup, its scoped CSS, and what reveals when, as
// [selector, sentence number] pairs.
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
};

// A scene's sub-composition: its timeline reveals each piece as the sentence
// naming it starts. A stills page sets window.__stills, so the timeline jumps
// to its end and stays unregistered: HyperFrames never seeks it back.
export function sceneFile(scene, timing, profile) {
  const id = scene.id;
  const f = {
    text: family(profile, "text"),
    title: family(profile, "title"),
    titleWeight: weight(profile, "title"),
    code: family(profile, "code"),
  };
  const c = COMPONENTS[scene.visual.component](scene.visual.props, f);
  const scope = `[data-composition-id="${id}"]`;
  const css = c.css
    .split("\n")
    .map((l) => `${scope} ${l}`)
    .join("\n");
  const reveals = c.reveals.map(([sel, at]) => [sel, timing.sentences[at - 1]]);
  return `<template id="${id}-template">
  <div data-composition-id="${id}" data-width="${W}" data-height="${H}" data-duration="${timing.duration}">
    <div class="content">${c.html}</div>
    <style>
${scope} .content { position: absolute; left: 80px; top: 178px; width: 1760px; height: 690px; }
${css}
    </style>
    <script>
      (function () {
        const tl = gsap.timeline({ paused: true });
        for (const [sel, t] of ${JSON.stringify(reveals)})
          tl.fromTo('${scope} ' + sel, { opacity: 0, y: 20 }, ${RISE}, t);
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
.header { position: absolute; left: 80px; right: 80px; top: 56px; height: 80px; display: flex; align-items: center; gap: 22px; border-bottom: 1px solid var(--line); }
.mark { width: 18px; height: 18px; border-radius: 4px; background: var(--accent); }
.kicker { font: 600 26px ${text}; color: var(--muted); letter-spacing: 0.04em; text-transform: uppercase; }
.captions { position: absolute; left: 80px; right: 80px; top: 908px; height: 104px; }
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
