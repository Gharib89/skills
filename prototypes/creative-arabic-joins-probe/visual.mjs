/* global document */
// Sets chosen words unsplit and in Remotion's ZWJ split, side by side, large,
// in HyperFrames' Chrome, to judge by eye whether the gate's flags are real.
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import puppeteer from "puppeteer-core";
import { FONTS, remotionUnits } from "./build.mjs";

const CASES = [
  ["amiri", "بتشغّل"],
  ["amiri", "الملف"],
  ["noto-nastaliq", "تسألك"],
  ["noto-nastaliq", "من"],
  ["noto-sans", "ده"],
  ["noto-sans", "بيقراه"],
  ["plex", "في"],
  ["plex", "الفرع"],
  ["cairo", "على"],
  ["tajawal", "متوصلة؟"],
];
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
const faces = Object.values(FONTS)
  .filter((f) => f.url)
  .map(
    (f) =>
      `@font-face{font-family:"${f.family}";src:url("../${f.url.slice(6)}")}`,
  )
  .join("");
const rows = CASES.map(
  ([k, w]) =>
    `<div class=r style='font-family:"${FONTS[k].family}"'><b>${k}</b><span>${w}</span><span class=s>${remotionUnits(
      w,
    )
      .map((u) => `<i>${u}</i>`)
      .join("")}</span></div>`,
).join("");
fs.mkdirSync("snap", { recursive: true });
fs.writeFileSync(
  "snap/visual.html",
  `<!doctype html><meta charset=utf-8><style>${faces}body{margin:0;background:#fff;width:1200px}.r{display:flex;align-items:center;gap:60px;font-size:84px;line-height:1.6;direction:rtl;border-bottom:1px solid #ddd;padding:0 30px}b{font:16px sans-serif;width:120px}.s i{display:inline-block;font-style:normal}</style>${rows}`,
);
const b = await puppeteer.launch({
  executablePath: chrome,
  headless: true,
  args: ["--no-sandbox"],
});
const p = await b.newPage();
await p.setViewport({ width: 1200, height: 800 });
await p.goto(`file://${root}/snap/visual.html`);
await p.evaluate(() => document.fonts.ready.then(() => 0));
await p.screenshot({ path: "snap/visual.png", fullPage: true });
await b.close();
