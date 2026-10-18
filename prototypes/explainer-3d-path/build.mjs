// PROTOTYPE: builds three HyperFrames compositions from a 72 s slice of the
// real dora-core composition (scenes context, trails, rubric), trails drawn as
// a 3D exploded stack:
//   live/   trails renders Three.js live inside the composer
//   clip3d/ the trails WebGL layer alone, 1920x760, rendered once to an MP4
//   clip/   trails is that MP4 as a clip insert, the HTML pins still live
//   flat/   the slice as dora-core shipped it, the 2D baseline
// usage: node build.mjs <dora-core composition dir> <work dir>
import fs from "node:fs";
import path from "node:path";

const [src, work] = process.argv.slice(2);
const here = path.dirname(new URL(import.meta.url).pathname);
const T0 = 26.69,
  T1 = 98.835,
  IDS = ["context", "trails", "rubric"];
const html = fs.readFileSync(path.join(src, "index.html"), "utf8");
const r3 = (x) => +x.toFixed(3);

const head = html.slice(0, html.indexOf("</head>"));
const header = html.match(/<div class="header"[^\n]*/)[0];
const hosts = [
  ...html.matchAll(
    /<div id="scene-(\w+)"[^>]*data-start="([\d.]+)" data-duration="([\d.]+)"[^>]*><\/div>/g,
  ),
]
  .filter((m) => IDS.includes(m[1]))
  .map((m) =>
    m[0].replace(`data-start="${m[2]}"`, `data-start="${r3(+m[2] - T0)}"`),
  );
const cues = [
  ...html.matchAll(/<div class="cue clip" data-start="([\d.]+)"[^\n]*<\/div>/g),
]
  .filter((m) => +m[1] >= T0 - 0.001 && +m[1] < T1)
  .map((m) =>
    m[0].replace(
      /data-(start|at)="([\d.]+)"/g,
      (_, k, v) => `data-${k}="${r3(+v - T0)}"`,
    ),
  );
const main = html.slice(
  html.lastIndexOf("<script>"),
  html.lastIndexOf("</script>") + 9,
);
const D = r3(T1 - T0);

const css = `
.t3d .gl { position: absolute; left: 0; top: 140px; width: 1920px; height: 760px; display: block; object-fit: fill; }
.t3d .pins { position: absolute; inset: 0; pointer-events: none; }
.t3d .anc { position: absolute; left: 0; top: 0; width: 0; height: 0; }
.t3d .anc > * { position: absolute; white-space: nowrap; }
.t3d .pill { padding: 10px 24px; border-radius: 999px; background: var(--text); color: #fff; font: 600 32px "google-sans-flex"; translate: 0 -100%; }
.t3d .pill.acc { background: var(--accent); }
.t3d .pill.ok { background: var(--ok); }
.t3d .pill.stop { background: var(--stop); }
.t3d .pill.chip { background: var(--chip); color: var(--text); translate: -50% -100%; }
.t3d .note { font: 400 26px "jetbrains-mono"; color: var(--muted); translate: 0 10px; }
.t3d .code { position: absolute; left: ${1920 - 14 * 12 - 24}px; top: ${140 + 760 - 12 - 16}px; display: flex; }
.t3d .code i { width: 12px; height: 12px; display: block; }`;

const scene = (body, opt) => `<template id="trails-template">
  <div data-composition-id="trails" data-width="1920" data-height="1080" data-duration="23.775">
    <div class="t3d">${body}</div>
    <style>${css}</style>
    <script>
      (function () {
        const host = document.querySelector('[data-composition-id="trails"] .t3d');
        const tl = Trails3D(host, ${JSON.stringify(opt)});
        window.__timelines = window.__timelines || {};
        if (window.__stills) tl.progress(1);
        else window.__timelines["trails"] = tl;
      })();
    </script>
  </div>
</template>
`;

const index = (title, total, body, extra = "") =>
  head
    .replace(/<title>.*<\/title>/, `<title>${title}</title>`)
    .replace(/data-duration="[\d.]+"/, "")
    .replace(
      '<script src="gsap.min.js"></script>',
      `<script src="gsap.min.js"></script>\n    <script src="three.global.js"></script>\n    <script src="trails3d.js"></script>${extra}`,
    ) +
  `</head>\n  <body>\n${body.replace("DUR", total)}\n  </body>\n</html>\n`;

const root = (name) =>
  `    <div id="root" data-composition-id="main" data-start="0" data-width="1920" data-height="1080" data-fps="30" data-duration="DUR">
      ${header}
${hosts.join("\n")}
      <div class="captions">
        ${cues.join("\n        ")}
      </div>
      <audio id="narration" src="narration.wav" data-start="0" data-duration="${D}" data-track-index="3" data-volume="1"></audio>
    </div>
    ${main}`;

function base(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(path.join(dir, "scenes"), { recursive: true });
  fs.cpSync(path.join(src, "fonts"), path.join(dir, "fonts"), {
    recursive: true,
  });
  for (const f of ["gsap.min.js"])
    fs.copyFileSync(path.join(src, f), path.join(dir, f));
  fs.copyFileSync(
    path.join(here, "vendor", "three.global.js"),
    path.join(dir, "three.global.js"),
  );
  fs.copyFileSync(
    path.join(here, "trails3d.js"),
    path.join(dir, "trails3d.js"),
  );
}

for (const v of ["live", "clip", "flat"]) {
  const dir = path.join(work, v);
  base(dir);
  for (const id of ["context", "rubric"])
    fs.copyFileSync(
      path.join(src, "scenes", `${id}.html`),
      path.join(dir, "scenes", `${id}.html`),
    );
  fs.writeFileSync(
    path.join(dir, "index.html"),
    index(`trails 3D ${v}`, D, root(v)),
  );
  fs.writeFileSync(
    path.join(dir, "scenes", "trails.html"),
    v === "flat"
      ? fs.readFileSync(path.join(src, "scenes", "trails.html"), "utf8")
      : v === "live"
        ? scene("", { canvas: true, pins: true, code: true })
        : scene(
            '<video class="gl" src="trails-3d.mp4" muted playsinline data-start="0" data-duration="23.775" data-track-index="0"></video>',
            { canvas: false, pins: true, code: false },
          ),
  );
}

// the clip: the WebGL layer and the frame strip alone, at the canvas size
const c3 = path.join(work, "clip3d");
base(c3);
fs.writeFileSync(
  path.join(c3, "index.html"),
  index(
    "trails 3D clip",
    23.775,
    `    <div id="root" data-composition-id="main" data-start="0" data-width="1920" data-height="760" data-fps="30" data-duration="DUR" style="width:1920px;height:760px;position:relative;overflow:hidden;background:#fff">
      <div class="t3d" style="position:absolute;left:0;top:-140px;width:1920px;height:1080px"></div>
    </div>
    <style>${css}\nhtml, body { width: 1920px; height: 760px; }</style>
    <script>
      (function () {
        const tl = Trails3D(document.querySelector(".t3d"), { canvas: true, pins: false, code: true });
        window.__timelines = window.__timelines || {};
        window.__timelines["main"] = tl;
      })();
    </script>`,
  ),
);
console.log(
  `built live, clip, clip3d in ${work}: ${hosts.length} scenes, ${cues.length} cues, ${D} s`,
);
