// The project's root, <run>/project/index.html, from timeline.json and the
// project as it stands: every scene host on the grid, over.html's host when
// that file exists, the captions host, the narration, and the kit's .css and
// .js sorted. timing.mjs writes it, and hf.mjs and render.mjs write it again
// before they use it, so an over.html or a kit file authored after the timing
// stage still reaches the check, the snapshots and the render.
import fs from "node:fs";
import path from "node:path";
import { readJson } from "../lib/json.mjs";

export const WIDTH = 1920;
export const HEIGHT = 1080;

export const esc = (s) =>
  s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

// One composition's host in the root, `style` its extra attribute.
export const host = (id, start, duration, track, kind, style = "") =>
  `    <div id="${id}" data-composition-id="${id}" data-composition-src="compositions/${id}.html" data-start="${start}" data-duration="${duration}" data-track-index="${track}" data-track-kind="${kind}" data-width="${WIDTH}" data-height="${HEIGHT}"${style}></div>`;

export function writeRoot(run) {
  const { total, scenes } = readJson(run, "timeline.json");
  const { language } = readJson(run, "script.json");
  const proj = path.join(run, "project");
  const kit = fs.existsSync(path.join(proj, "kit"))
    ? fs.readdirSync(path.join(proj, "kit")).sort()
    : [];
  const head = [
    ...kit
      .filter((f) => f.endsWith(".css"))
      .map((f) => `    <link rel="stylesheet" href="kit/${f}" />`),
    ...kit
      .filter((f) => f.endsWith(".js"))
      .map((f) => `    <script src="kit/${f}"></script>`),
  ];
  const hosts = [
    ...scenes.map((s) => host(s.id, s.start, s.duration, 1, "graphics")),
    ...(fs.existsSync(path.join(proj, "compositions", "over.html"))
      ? [host("over", 0, total, 2, "graphics")]
      : []),
    host("captions", 0, total, 3, "captions", ' style="z-index:10"'),
  ];
  fs.writeFileSync(
    path.join(proj, "index.html"),
    `<!doctype html>
<html lang="${language}">
  <head>
    <meta charset="utf-8" />
    <title>${esc(path.basename(path.resolve(run)))}</title>
    <style>
      body {
        margin: 0;
      }
    </style>
    <script src="assets/gsap.min.js"></script>
    <script src="timing.js"></script>
${[...head, "  </head>"].join("\n")}
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="${total}" data-width="${WIDTH}" data-height="${HEIGHT}">
${hosts.join("\n")}
      <audio id="narration" class="clip" src="assets/narration.wav" data-start="0" data-duration="${total}" data-volume="1" data-track-index="4"></audio>
    </div>
    <script>
      window.__timelines["main"] = gsap.timeline({ paused: true });
    </script>
  </body>
</html>
`,
  );
}
