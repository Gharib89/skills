// The project's root, <run>/project/index.html, from timeline.json and the
// project as it stands: every scene host on the grid whose file exists,
// over.html's host when that file exists, the captions host, the narration, and
// the kit's .css and .js sorted. timing.mjs writes it, and hf.mjs and render.mjs
// write it again before they use it, so an over.html or a kit file authored
// after the timing stage still reaches the check, the snapshots and the render.
// A video in chapters has chapter 1's scene files before the rest, and a host
// naming a file that is not there breaks the CLI, so the root hosts only the
// files that exist: the gates and the render refuse a missing file themselves.
// rootHtml is the shape a chapter's root (render/chapter-project.mjs) shares.
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

// The captions' host, over every other, `duration` long.
export const captionsHost = (duration) =>
  host("captions", 0, duration, 3, "captions", ' style="z-index:10"');

// A root of `hosts` in the project folder `proj`, `total` seconds long, its
// <head> loading the kit's .css and .js sorted, with the narration clip unless
// `narration` is false.
export function rootHtml({ proj, title, language, total, hosts, narration }) {
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
  const clip = narration
    ? `\n      <audio id="narration" class="clip" src="assets/narration.wav" data-start="0" data-duration="${total}" data-volume="1" data-track-index="4"></audio>`
    : "";
  return `<!doctype html>
<html lang="${language}">
  <head>
    <meta charset="utf-8" />
    <title>${esc(title)}</title>
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
${hosts.join("\n")}${clip}
    </div>
    <script>
      window.__timelines["main"] = gsap.timeline({ paused: true });
    </script>
  </body>
</html>
`;
}

export function writeRoot(run) {
  const { total, scenes } = readJson(run, "timeline.json");
  const { language } = readJson(run, "script.json");
  const proj = path.join(run, "project");
  const has = (id) =>
    fs.existsSync(path.join(proj, "compositions", `${id}.html`));
  const hosts = [
    ...scenes
      .filter((s) => has(s.id))
      .map((s) => host(s.id, s.start, s.duration, 1, "graphics")),
    ...(has("over") ? [host("over", 0, total, 2, "graphics")] : []),
    captionsHost(total),
  ];
  fs.writeFileSync(
    path.join(proj, "index.html"),
    rootHtml({
      proj,
      title: path.basename(path.resolve(run)),
      language,
      total,
      hosts,
      narration: true,
    }),
  );
}
