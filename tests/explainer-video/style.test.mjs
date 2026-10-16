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

test("a website's declared colours count only where its pages show them", () => {
  const { run, env } = fixture();
  env.EXPLAINER_VIDEO_FAKE_SITE = JSON.stringify({
    "https://acme.test/": {
      pages: [SLIDE, SLIDE],
      colors: ["#cc6c55", "#00ff00"],
      fonts: ["Source Serif 4"],
    },
  });
  const r = node("measure.mjs", [run, "https://acme.test/"], env);
  assert.equal(r.status, 0, r.stderr);
  const c = candidates(run);
  assert.deepEqual(
    c.images.map((i) => i.name),
    ["acme-test-1.ppm", "acme-test-2.ppm"],
  );
  assert.deepEqual(c.accents[0], {
    id: "a1",
    hex: "#cc6c55",
    share: 0.06,
    images: ["acme-test-1.ppm", "acme-test-2.ppm"],
    declared: true,
  });
  assert.ok(![...c.surfaces, ...c.accents].some((x) => x.hex === "#00ff00"));
  assert.deepEqual(c.fonts, ["Source Serif 4"]);
  assert.match(
    r.stdout,
    /^style declared #00ff00: not in the reference images, dropped$/m,
  );
  const call = fs
    .readFileSync(env.EXPLAINER_VIDEO_FAKE_LOG, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l))
    .find((l) => l.call === "capturePages");
  assert.equal(call.max, 5);
});

test("a deck and a video become at most twelve images each", () => {
  const { run, docs, env } = fixture();
  fs.writeFileSync(path.join(docs, "deck.pdf"), "pdf");
  fs.writeFileSync(path.join(docs, "talk.mp4"), "mp4");
  env.EXPLAINER_VIDEO_FAKE_FRAMES = "15";
  const r = node(
    "measure.mjs",
    [run, path.join(docs, "deck.pdf"), path.join(docs, "talk.mp4")],
    env,
  );
  assert.equal(r.status, 0, r.stderr);
  const names = candidates(run).images.map((i) => i.name);
  assert.equal(names.filter((n) => n.startsWith("deck-")).length, 12);
  assert.equal(names.filter((n) => n.startsWith("talk-")).length, 12);
  assert.match(r.stdout, /^style ref deck-1\.ppm: pdf · /m);
  assert.match(r.stdout, /^style ref talk-1\.ppm: video · /m);
});

test("a PPTX alone has no pixels; beside its PDF its theme confirms colours", () => {
  const { run, docs, env } = fixture();
  const deck = path.join(docs, "deck.pptx");
  // The fake unzip reads a JSON file of parts.
  fs.writeFileSync(
    deck,
    JSON.stringify({
      parts: {
        "ppt/theme/theme1.xml":
          '<a:theme><a:themeElements><a:clrScheme name="Acme"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:accent1><a:srgbClr val="CC6C55"/></a:accent1></a:clrScheme><a:fontScheme><a:majorFont><a:latin typeface="Georgia"/></a:majorFont><a:minorFont><a:latin typeface="Inter"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>',
      },
    }),
  );
  const alone = node("measure.mjs", [run, deck], env);
  assert.equal(alone.status, 1);
  assert.match(alone.stderr, /export the deck to PDF/);
  assert.ok(!fs.existsSync(path.join(run, "style-draft", "candidates.json")));

  fs.writeFileSync(path.join(docs, "deck.pdf"), "pdf");
  const both = node(
    "measure.mjs",
    [run, deck, path.join(docs, "deck.pdf")],
    env,
  );
  assert.equal(both.status, 0, both.stderr);
  const c = candidates(run);
  assert.equal(c.accents[0].hex, "#cc6c55");
  assert.deepEqual(c.fonts, ["Georgia", "Inter"]);
  assert.match(
    both.stdout,
    /^style declared #000000: not in the reference images, dropped$/m,
  );
});
