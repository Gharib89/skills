/* global document, window */
// Drives each composition in HyperFrames' own Chrome, seeks its GSAP timeline
// to the sample frames, and measures every Arabic box three ways per word:
//   width:  the split copy's advance width against the unsplit word's
//   shaped: HarfBuzz glyph ids of the copy's shaping runs against the word's
//   pixels: ink of the split copy against ink of the unsplit word
// Writes results.json; summarise.mjs scores it against truth.json.
import fs from "node:fs";

import path from "node:path";
import { execFileSync } from "node:child_process";
import puppeteer from "puppeteer-core";
import { PNG } from "pngjs";
import * as hb from "harfbuzzjs";
import { FONTS } from "./build.mjs";

const TIMES = (process.env.TIMES ?? "0.3,1.0,3.0").split(",").map(Number);
const ONLY = process.env.FONTS?.split(",");
const root = path.dirname(new URL(import.meta.url).pathname);
const chrome = execFileSync(
  process.execPath,
  [
    path.join(root, "node_modules/hyperframes/bin/hyperframes.mjs"),
    "browser",
    "path",
  ],
  { encoding: "utf8" },
)
  .trim()
  .split("\n")
  .at(-1);

// HarfBuzz: glyph ids and offsets (a mark sits by offset) of a string's
// shaping, ZWJ's own glyph dropped.
const shapers = {};
function shaper(key) {
  if (shapers[key]) return shapers[key];
  const file = FONTS[key].file;
  const face = new hb.Face(
    new hb.Blob(fs.readFileSync(path.resolve(root, file))),
  );
  const font = new hb.Font(face);
  const run = (text) => {
    const buf = new hb.Buffer();
    buf.addText(text);
    buf.guessSegmentProperties();
    buf.setDirection(hb.Direction.RTL);
    hb.shape(font, buf);
    const pos = buf.getGlyphPositions();
    return buf.getGlyphInfos().map((g, i) => ({
      g: g.codepoint,
      cl: g.cluster,
      ax: pos[i].xAdvance,
      dx: pos[i].xOffset,
      dy: pos[i].yOffset,
    }));
  };
  const zwj = new Set(run("‍").map((x) => x.g));
  const ids = (text) =>
    run(text)
      .filter((x) => !(zwj.has(x.g) && x.ax === 0))
      .map((x) => `${x.g}@${x.dx},${x.dy}`);
  return (shapers[key] = ids);
}

// Ink mask of a crop: dark pixels on the white overlay.
function ink(png, r, pad) {
  const x0 = Math.max(0, Math.floor(r.x - pad.x)),
    y0 = Math.max(0, Math.floor(r.y - pad.y));
  const x1 = Math.min(png.width, Math.ceil(r.x + r.w + pad.x)),
    y1 = Math.min(png.height, Math.ceil(r.y + r.h + pad.y));
  const pts = [];
  for (let y = y0; y < y1; y++)
    for (let x = x0; x < x1; x++) {
      const i = (y * png.width + x) * 4;
      if (png.data[i] + png.data[i + 1] + png.data[i + 2] < 3 * 128)
        pts.push([x, y]);
    }
  if (!pts.length) return { set: new Set(), n: 0 };
  // Anchor at the ink's top-right corner: Arabic starts on the right.
  const maxX = Math.max(...pts.map((p) => p[0])),
    minY = Math.min(...pts.map((p) => p[1]));
  return {
    set: new Set(pts.map(([x, y]) => `${maxX - x},${y - minY}`)),
    n: pts.length,
  };
}
// 1 - IoU of two ink masks, best over a one-pixel shift either way.
function pixelDiff(a, b) {
  if (!a.n && !b.n) return 0;
  let best = 1;
  for (let dx = -1; dx <= 1; dx++)
    for (let dy = -1; dy <= 1; dy++) {
      let both = 0;
      for (const k of a.set) {
        const [x, y] = k.split(",").map(Number);
        if (b.set.has(`${x + dx},${y + dy}`)) both++;
      }
      best = Math.min(best, 1 - both / (a.n + b.n - both));
    }
  return best;
}

const browser = await puppeteer.launch({
  executablePath: chrome,
  headless: true,
  protocolTimeout: 60000,
  args: ["--no-sandbox", "--font-render-hinting=none"],
});
const page = await browser.newPage();
await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
const measureJs = fs.readFileSync(path.join(root, "measure.js"), "utf8");
const results = [];
const cost = { width: [], shaped: [], pixels: [] };
for (const key of Object.keys(FONTS).filter((k) => !ONLY || ONLY.includes(k))) {
  await page.goto(`file://${root}/comp/${key}/index.html`, {
    waitUntil: "load",
  });
  await page.evaluate(() =>
    document.fonts.ready.then(() => document.fonts.size),
  );
  await page.evaluate(measureJs);
  const ids = await page.$$eval(".box", (els) => els.map((e) => e.id));
  const shape = shaper(key);
  const em = 44;
  for (const t of TIMES) {
    for (const id of ids) {
      await page.evaluate(
        (t) => void window.__timelines.main.seek(t, false),
        t,
      );
      let t0 = performance.now();
      const words = await page.evaluate((id) => window.__arabicJoins(id), id);
      const domMs = performance.now() - t0;
      cost.width.push(domMs);
      t0 = performance.now();
      const shot = PNG.sync.read(
        Buffer.from(
          await page.screenshot({
            type: "png",
            clip: { x: 0, y: 0, width: 1920, height: 1080 },
          }),
        ),
      );
      const pix = words.map((w) =>
        pixelDiff(
          ink(shot, w.split, { x: 2, y: em * 0.4 }),
          ink(shot, w.whole, { x: 2, y: em * 0.4 }),
        ),
      );
      cost.pixels.push(performance.now() - t0 + domMs);
      t0 = performance.now();
      const shaped = words.map((w) => {
        const a = w.runs.flatMap((r) => shape(r).reverse()).join(",");
        const b = shape(w.text).reverse().join(",");
        return a === b;
      });
      cost.shaped.push(performance.now() - t0 + domMs);
      words.forEach((w, i) =>
        results.push({
          font: key,
          box: id,
          t,
          word: i,
          text: w.text,
          runs: w.runs.length,
          dw: w.split.w - w.whole.w,
          pix: pix[i],
          same: shaped[i],
        }),
      );
    }
    process.stderr.write(`${key} t=${t} done\n`);
  }
}
await browser.close();

const med = (a) => a.sort((x, y) => x - y)[Math.floor(a.length / 2)];
fs.writeFileSync(
  "results.json",
  JSON.stringify({
    cost: Object.fromEntries(
      Object.entries(cost).map(([k, v]) => [
        k,
        { median: med(v), max: Math.max(...v), n: v.length },
      ]),
    ),
    results,
  }),
);
console.log(JSON.stringify(JSON.parse(fs.readFileSync("results.json")).cost));
