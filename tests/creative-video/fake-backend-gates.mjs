// Canned gate measures: HyperFrames' check, the text probe, the snapshots and
// their pixels, answering from the authored scene files. A scene file built to
// fail holds a marker word, its passing twin the same file without it:
//   clipped       a text_box_overflow layout error on the scene
//   once-clip, once-overlap, once-spill  a text_box_overflow, content_overlap
//                 or container_overflow seen at the key sample only, which
//                 HyperFrames grades info
//   low-contrast  a contrast_aa_failure (a warning, as HyperFrames grades it)
//   in-band       the text sits at y 900, in the bottom 220 px
//   tiny          12 px text; `edge` sits at x 40, outside the safe margin
//   faint         opacity 0.5; `blink` is shown only 0.25 to 0.75 s into its scene;
//                 `hidden` is never shown, opacity 0
//   tl.<call>(... Date.now() or performance.now() ...) the scene's snapshots
//                 differ between two launches
//   at("<id>", "<word>")  a word the timeline lacks is a console_error, as the
//                 browser running the scene's script reports it
//   throw new Error("<text>")  the same console_error with the thrown text
//   no-timeline   the scene registers no timeline and no error is reported,
//                 as HyperFrames 0.8.206 does for a throwing script that also
//                 names a second timeline
//   data-tween="<a>-<b>" and data-sound="<t>" the scene's tween windows and
//                 sounds, in scene seconds (no tween: one across the scene)
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { NO_WORD } from "../../skills/creative-video/scripts/render/anchors.mjs";
import { log } from "./fake-backend-log.mjs";

const norm = (s) => s.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");

// Each mounted scene's id, window and file text, the captions' too.
function mounted(dir) {
  const html = fs.readFileSync(path.join(dir, "index.html"), "utf8");
  return [
    ...html.matchAll(
      /data-composition-id="([^"]+)" data-composition-src="[^"]+" data-start="([\d.]+)" data-duration="([\d.]+)"/g,
    ),
  ].map((m) => ({
    id: m[1],
    start: +m[2],
    end: +m[2] + +m[3],
    html: fs.readFileSync(
      path.join(dir, "compositions", `${m[1]}.html`),
      "utf8",
    ),
  }));
}
const sceneAt = (dir, t) =>
  mounted(dir).find((m) => m.id !== "captions" && t >= m.start && t < m.end);

// The text elements the file draws at scene-local `local`.
function texts(m, local) {
  if (m.id === "captions")
    return [
      ...m.html.matchAll(
        /<div class="cue clip" data-start="([\d.]+)" data-duration="([\d.]+)"[^>]*>(.*?)<\/div>/g,
      ),
    ]
      .filter(
        (c) => local + m.start >= +c[1] && local + m.start < +c[1] + +c[2],
      )
      .map((c) => ({
        text: c[3].replace(/<[^>]+>/g, ""),
        top: 920,
        fontPx: 44,
        opacity: 1,
        left: 160,
      }));
  let row = 0;
  return [...m.html.matchAll(/<(p|h1|span|div)\b([^>]*)>([^<]+)<\/\1>/g)]
    .filter((e) => e[3].trim() && !e[2].includes("data-layout-ignore"))
    .map((e) => {
      const text = e[3].trim();
      const has = (w) => new RegExp(`\\b${w}\\b`).test(text);
      return {
        text,
        top: has("in-band") ? 900 : 200 + 50 * row++,
        left: has("edge") ? 40 : 160,
        fontPx: has("tiny") ? 12 : 40,
        opacity: has("faint")
          ? 0.5
          : has("hidden")
            ? 0
            : has("blink") && !(local >= 0.25 && local < 0.75)
              ? 0
              : 1,
      };
    });
}

// The console error the browser reports when a scene's script throws.
const scriptError = (scene, what) => ({
  code: "console_error",
  severity: "error",
  time: 0,
  sourceFile: "index.html",
  message: `[HyperFrames] composition script error: ${scene} ${what}`,
});

export async function check(dir, times) {
  log({ call: "check", times });
  const layout = [];
  const contrast = [];
  const runtime = [];
  const timeline = JSON.parse(
    fs.readFileSync(path.join(dir, "..", "timeline.json"), "utf8"),
  );
  for (const m of mounted(dir).filter((m) => m.id !== "captions")) {
    const mine = times.filter((t) => t >= m.start && t < m.end);
    const found = (word) =>
      texts(m, 0).filter((e) => new RegExp(`\\b${word}\\b`).test(e.text));
    for (const e of found("clipped"))
      if (mine.length)
        layout.push({
          code: "text_box_overflow",
          severity: "error",
          time: mine[0],
          times: mine,
          text: e.text,
          sourceFile: `compositions/${m.id}.html`,
        });
    const once = {
      "once-clip": "text_box_overflow",
      "once-overlap": "content_overlap",
      "once-spill": "container_overflow",
    };
    for (const [marker, code] of Object.entries(once))
      for (const e of found(marker))
        if (mine.length > 1)
          layout.push({
            code,
            severity: "info",
            time: mine[1],
            times: [mine[1]],
            occurrences: 1,
            text: e.text,
            sourceFile: `compositions/${m.id}.html`,
          });
    for (const e of found("low-contrast"))
      if (mine.length)
        contrast.push({
          code: "contrast_aa_failure",
          severity: "warning",
          time: mine[0],
          text: e.text,
          ratio: 2.1,
          requiredRatio: 4.5,
          sourceFile: `compositions/${m.id}.html`,
        });
    for (const a of m.html.matchAll(
      /at\("([^"]+)", "([^"]+)"(?:, (\d+))?\)/g,
    )) {
      const words = (
        timeline.scenes.find((s) => s.id === a[1])?.words ?? []
      ).filter((w) => norm(w.text) === norm(a[2]));
      if (!words[(+a[3] || 1) - 1])
        runtime.push(
          scriptError(
            m.id,
            `Error: ${NO_WORD} "${a[2]}" (${+a[3] || 1}) in scene ${a[1]}`,
          ),
        );
    }
    for (const t of m.html.matchAll(/throw new Error\("([^"]*)"\)/g))
      runtime.push(scriptError(m.id, `Error: ${t[1]}`));
  }
  const section = (findings) => ({ ok: !findings.length, findings });
  return {
    ok: !layout.length && !runtime.length,
    runtime: section(runtime),
    layout: section(layout),
    contrast: section(contrast),
    craft: section([]),
  };
}

export async function probe(dir, times) {
  log({ call: "probe", times });
  const frames = times.map((t) => {
    const out = [];
    for (const m of mounted(dir))
      if (t >= m.start && t < m.end)
        for (const e of texts(m, t - m.start))
          out.push({
            text: e.text,
            words: e.text.split(/\s+/).length,
            scene: m.id,
            rect: { left: e.left, top: e.top, right: 1760, bottom: e.top + 48 },
            fontPx: e.fontPx,
            opacity: e.opacity,
          });
    return { t, texts: out };
  });
  const events = {};
  for (const m of mounted(dir).filter((m) => m.id !== "captions")) {
    if (/\bno-timeline\b/.test(m.html)) continue;
    const tweens = [...m.html.matchAll(/data-tween="([\d.]+)-([\d.]+)"/g)].map(
      (w) => [+w[1], +w[2]],
    );
    events[m.id] = {
      tweens: tweens.length ? tweens : [[0, m.end - m.start]],
      sounds: [...m.html.matchAll(/data-sound="([\d.]+)"/g)].map((s) => +s[1]),
    };
  }
  return { frames, events };
}

// Each frame's "pixels" are its time and scene; a scene whose timeline reads the
// wall clock adds a fresh draw, so two launches disagree.
export async function snapshot(dir, times, outDir) {
  log({ call: "snapshot", times, outDir });
  fs.mkdirSync(outDir, { recursive: true });
  return times.map((time, i) => {
    const file = path.join(
      outDir,
      `frame-${String(i).padStart(2, "0")}-at-${time}s.png`,
    );
    const m = sceneAt(dir, time);
    const draw = /\btl\.[^;]*\b(Date|performance)\.now\(\)/.test(m?.html ?? "")
      ? Math.random()
      : "";
    fs.writeFileSync(file, `pixels ${m?.id} ${time} ${draw}`);
    return { path: file, time };
  });
}

export async function framePixels(png) {
  log({ call: "framePixels", png });
  return crypto.createHash("sha256").update(fs.readFileSync(png)).digest("hex");
}
