// Style extraction through its process doors: sources turned into reference
// images and measured into colour candidates, then roles assigned by id and a
// draft profile written. The fake backend stands in for Chrome, pdf.js and
// ffmpeg: every reference image it writes or decodes is a binary PPM.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import { loadStyle } from "../../skills/explainer-video/scripts/lib/style.mjs";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const scripts = path.join(
  here,
  "..",
  "..",
  "skills",
  "explainer-video",
  "scripts",
  "style",
);

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// A binary PPM of `w` by `h`, filled top to bottom by `bands`, each
// `[hex, rows]`.
function ppm(w, bands) {
  const h = bands.reduce((n, [, rows]) => n + rows, 0);
  const head = Buffer.from(`P6\n${w} ${h}\n255\n`);
  const px = Buffer.alloc(w * h * 3);
  let o = 0;
  for (const [hex, rows] of bands)
    for (let i = 0; i < w * rows; i++) {
      px[o++] = parseInt(hex.slice(1, 3), 16);
      px[o++] = parseInt(hex.slice(3, 5), 16);
      px[o++] = parseInt(hex.slice(5, 7), 16);
    }
  return Buffer.concat([head, px]);
}

// A cream slide: ground, white panel, dark text, a clay accent.
const SLIDE = [
  ["#f5f4ed", 70],
  ["#ffffff", 14],
  ["#141413", 10],
  ["#cc6c54", 6],
];
// The same look with no colour above the saturation floor.
const GREY = [
  ["#f5f4ed", 80],
  ["#141413", 20],
];

function fixture({ tools = true } = {}) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-style-"));
  temps.push(tmp);
  const env = {
    PATH: process.env.PATH,
    HOME: path.join(tmp, "home"),
    XDG_CACHE_HOME: path.join(tmp, "cache"),
    EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
    EXPLAINER_VIDEO_FAKE_LOG: path.join(tmp, "calls.jsonl"),
  };
  if (tools)
    for (const r of catalogue().filter((r) =>
      ["npm", "chrome"].includes(r.kind),
    )) {
      const d = dest(r, userDirs({ platform: "linux", env, home: env.HOME }));
      fs.mkdirSync(d, { recursive: true });
      fs.writeFileSync(path.join(d, ".stamp"), "");
    }
  const run = path.join(tmp, "proj", "explainers", "acme");
  fs.mkdirSync(run, { recursive: true });
  const docs = path.join(tmp, "docs");
  fs.mkdirSync(docs);
  return { tmp, run, docs, env };
}

const node = (script, args, env) =>
  spawnSync(process.execPath, [path.join(scripts, script), ...args], {
    env,
    encoding: "utf8",
  });

const candidates = (run) =>
  JSON.parse(
    fs.readFileSync(path.join(run, "style-draft", "candidates.json"), "utf8"),
  );

test("screenshots measure into the same candidates every time", () => {
  const { run, docs, env } = fixture();
  fs.writeFileSync(path.join(docs, "one.png"), ppm(50, SLIDE));
  fs.writeFileSync(path.join(docs, "two.png"), ppm(50, SLIDE));
  const args = [run, path.join(docs, "one.png"), path.join(docs, "two.png")];
  const first = node("measure.mjs", args, env);
  assert.equal(first.status, 0, first.stderr);
  const kept = fs.readFileSync(
    path.join(run, "style-draft", "candidates.json"),
    "utf8",
  );
  const again = node("measure.mjs", args, env);
  assert.equal(again.status, 0, again.stderr);
  assert.equal(
    fs.readFileSync(path.join(run, "style-draft", "candidates.json"), "utf8"),
    kept,
  );

  const c = candidates(run);
  assert.deepEqual(
    c.images.map((i) => i.name),
    ["one-1.png", "two-1.png"],
  );
  assert.deepEqual(
    c.surfaces.map((s) => s.hex),
    ["#f5f4ed", "#ffffff", "#141413", "#cc6c54"],
  );
  assert.deepEqual(c.surfaces[0].images, ["one-1.png", "two-1.png"]);
  assert.equal(c.surfaces[0].share, 0.7);
  assert.deepEqual(
    c.accents.map((a) => a.hex),
    ["#cc6c54"],
  );
  assert.match(
    first.stdout,
    /^style candidate a1: #cc6c54 · 6% · one-1\.png, two-1\.png$/m,
  );
  assert.match(first.stdout, /^style: measured 2 reference image\(s\) -> /m);
});
