// Canned gate measures: what the composition shows at a time, the layout
// check and the text probe.
import fs from "node:fs";
import path from "node:path";
import { log } from "./fake-backend-log.mjs";

// What shows at t: each mounted scene's own text elements, and the caption
// cue's words joined.
export function showing(dir, t) {
  const html = fs.readFileSync(path.join(dir, "index.html"), "utf8");
  const on = (start, duration) => t >= +start && t < +start + +duration;
  const texts = [];
  for (const m of html.matchAll(
    /data-composition-id="([^"]+)" data-composition-src="[^"]+" data-start="([\d.]+)" data-duration="([\d.]+)"/g,
  ))
    if (on(m[2], m[3])) {
      // A line of the type family `words` reads as the one box it is: the
      // canned measure has no per-word rects.
      const scene = fs
        .readFileSync(path.join(dir, "scenes", `${m[1]}.html`), "utf8")
        .replace(/<span class="w"><span class="wi k\d+">/g, "")
        .replace(/<\/span><\/span>/g, "");
      // Each element's `dir`, or null, open around the text: the nearest one
      // outside it is the box it sits in.
      const dirs = [];
      for (const e of scene.matchAll(
        /<(\/?)(div|span|bdi)\b([^>]*)>([^<]*)/g,
      )) {
        if (e[1]) {
          dirs.pop();
          continue;
        }
        const within = dirs.findLast(Boolean) ?? null;
        const own = e[3].match(/\sdir="(\w+)"/)?.[1] ?? null;
        dirs.push(own);
        if (e[4].trim())
          texts.push({
            scene: m[1],
            start: +m[2],
            text: e[4].trim(),
            bdi: e[2] === "bdi",
            rtl: (own ?? within) === "rtl",
            within,
          });
      }
    }
  for (const m of html.matchAll(
    /<div class="cue clip" data-start="([\d.]+)" data-duration="([\d.]+)"[^>]*>(.*?)<\/div>/g,
  ))
    if (on(m[1], m[2])) {
      // A Latin run's <bdi> is an element of its own, as the browser sees it.
      const text = m[3]
        .replace(/<bdi[^>]*>[^<]*<\/bdi>/g, "")
        .replace(/<[^>]+>/g, "")
        .replace(/\s+/g, " ")
        .trim();
      const rtl = /^[^>]* dir="rtl"/.test(m[0]);
      if (text) texts.push({ scene: null, text, rtl });
      for (const r of m[3].matchAll(/<bdi[^>]*>([^<]+)<\/bdi>/g))
        texts.push({ scene: null, text: r[1], bdi: true, rtl });
    }
  return { html, texts };
}

// A scene's timeline events, as the real backend reads them off its GSAP
// timeline: tween ends and the `seam:` and `camera:` label pairs, in scene
// seconds. EXPLAINER_VIDEO_FAKE_EVENTS is a JSON object of scene id to
// {ends, seams, camera}; a scene it omits has the seam and camera windows its
// own script labels (`addLabel("seam:start", a)` ... `addLabel("seam:end", b)`)
// and no other event.
export async function events(dir) {
  log({ call: "events", dir });
  const out = {};
  const scenes = path.join(dir, "scenes");
  for (const f of fs.existsSync(scenes) ? fs.readdirSync(scenes) : []) {
    const html = fs.readFileSync(path.join(scenes, f), "utf8");
    const at = (label, edge) =>
      Object.fromEntries(
        [
          ...html.matchAll(
            new RegExp(
              `addLabel\\("${label}:${edge}(\\d*)", ([\\d.]+)\\)`,
              "g",
            ),
          ),
        ].map((m) => [m[1], +m[2]]),
      );
    // an unpaired start is no window, as the real adapter reads it
    const windows = (label) => {
      const [start, end] = [at(label, "start"), at(label, "end")];
      return Object.keys(start)
        .filter((k) => k in end)
        .map((k) => [start[k], end[k]]);
    };
    const [seams, camera] = [windows("seam"), windows("camera")];
    if (seams.length || camera.length)
      out[f.replace(/\.html$/, "")] = {
        ...(seams.length && { seams }),
        ...(camera.length && { camera }),
      };
  }
  return {
    ...out,
    ...JSON.parse(process.env.EXPLAINER_VIDEO_FAKE_EVENTS ?? "{}"),
  };
}

export async function check(dir, times) {
  log({ call: "check", times });
  if (process.env.EXPLAINER_VIDEO_FAKE_CHECK)
    return JSON.parse(process.env.EXPLAINER_VIDEO_FAKE_CHECK);
  const findings = times.flatMap((t) =>
    showing(dir, t)
      .texts.filter((e) => /\bclipped\b/.test(e.text))
      .map((e) => ({
        code: "text_box_overflow",
        severity: "error",
        time: t,
        message: "text overflows its box",
        text: e.text,
        sourceFile: `scenes/${e.scene}.html`,
      })),
  );
  return {
    ok: !findings.length,
    layout: { findings },
    contrast: { findings: [] },
  };
}

// An element's reading direction as the composition sets it: Arabic text reads
// right to left in a box or cue marked so, and `within` is the `dir` of the
// box a scene's element sits in; a Latin run's <bdi> sits in one, isolated
// unless the `.lat` rule says otherwise, on one line where it says so. A caption
// word's line height is the `.cue` rule's, against the ink Arabic's letters
// span in a caption's IBM Plex Sans Arabic, as the real probe measured it on a
// live render (1.35 em, Chromium 152).
function reading(html, scene, text, bdi, rtl, within) {
  const cue = html.match(
    /\.cue \{[^}]*font: \d+ (?:[\d.]+px|var\(--size-\w+\))\/([\d.]+) "([^"]+)"/,
  );
  const arabic = /\p{Script=Arabic}/u.test(text);
  return {
    dir: arabic && rtl ? "rtl" : "ltr",
    within: within !== undefined ? within : bdi && rtl ? "rtl" : null,
    bidi:
      bdi && !/\.lat \{[^}]*unicode-bidi: normal/.test(html)
        ? "isolate"
        : "normal",
    wrap:
      bdi && /\.lat \{[^}]*white-space: nowrap/.test(html)
        ? "nowrap"
        : "normal",
    lineH: scene === null && cue ? +cue[1] : null,
    face: cue?.[2] ?? null,
    ink: 1.35,
  };
}

// An element naming `fading` is mid-reveal (opacity 0.4) until
// EXPLAINER_VIDEO_FAKE_FADE_END scene seconds (default 1), then fully shown.
const fading = (text, since) =>
  /\bfading\b/.test(text) &&
  since < +(process.env.EXPLAINER_VIDEO_FAKE_FADE_END ?? 1)
    ? 0.4
    : 1;

export async function probe(dir, times) {
  log({ call: "probe", times });
  return times.map((t) => {
    const { html, texts } = showing(dir, t);
    const color = (k) => html.match(new RegExp(`--${k}: (#[0-9a-f]{6});`))[1];
    if (process.env.EXPLAINER_VIDEO_FAKE_BLANK) return { t, elements: [] };
    return {
      t,
      elements: texts.map(({ scene, start, text, bdi, rtl, within }, i) => {
        const row = /\bstacked\b/.test(text) ? i - 0.5 : i;
        const top = scene ? 200 + row * 50 : 920;
        const left = /\bedge\b/.test(text) ? 40 : 160;
        const rect = { left, top, right: 1760, bottom: top + 48 };
        const clipped = /\bclipped\b/.test(text);
        return {
          text,
          scene,
          rect,
          fontPx: /\btiny\b/.test(text) ? 12 : /\bsmall\b/.test(text) ? 20 : 40,
          weight: 400,
          inline: false,
          scrollW: clipped ? 4000 : 1600,
          scrollH: 48,
          words: text.split(/\s+/).length,
          clientW: 1600,
          clientH: 48,
          opacity: fading(text, t - start),
          clip: clipped ? { ...rect, right: 1000 } : null,
          color: /\bdim\b/.test(text)
            ? "#c8c8c0"
            : /\bsmall\b/.test(text)
              ? color("accent")
              : color("text"),
          bg: color("bg"),
          ...reading(html, scene, text, bdi, rtl, within),
        };
      }),
      rootDir: [
        ["html", /<html[^>]*\sdir=/],
        ["body", /<body[^>]*\sdir=/],
        ["#root", /<div id="root"[^>]*\sdir=/],
      ]
        .filter(([, re]) => re.test(html))
        .map(([r]) => r),
    };
  });
}
