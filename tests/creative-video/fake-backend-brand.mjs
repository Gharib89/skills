// Canned brand readers: pages, PDF pages and video frames that are PPM images
// of colour bands, so each colour's area share is known.
import fs from "node:fs";
import path from "node:path";
import { log } from "./fake-backend-log.mjs";

// A binary PPM 50 wide, filled top to bottom by the bands, each `[hex, rows]`:
// the fake's every captured page, PDF page and video frame, written under the
// `.png` name the real capture gives it, and what `ppm` reads back.
export function bandsPpm(bands) {
  const w = 50;
  const h = bands.reduce((n, [, rows]) => n + rows, 0);
  const px = Buffer.alloc(w * h * 3);
  let o = 0;
  for (const [hex, rows] of bands)
    for (let i = 0; i < w * rows; i++)
      for (const at of [1, 3, 5]) px[o++] = parseInt(hex.slice(at, at + 2), 16);
  return Buffer.concat([Buffer.from(`P6\n${w} ${h}\n255\n`), px]);
}

// A cream slide: ground, white panel, dark text, a clay accent.
export const SLIDE = [
  ["#f5f4ed", 70],
  ["#ffffff", 14],
  ["#141413", 10],
  ["#cc6c54", 6],
];

function writeImages(out, list) {
  fs.mkdirSync(path.dirname(out), { recursive: true });
  return list.map((bands, n) => {
    const f = `${out}-${n + 1}.png`;
    fs.writeFileSync(f, bandsPpm(bands));
    return f;
  });
}

// CREATIVE_VIDEO_FAKE_SITE maps a URL to `{ pages, colors, fonts }`, each page
// a list of bands.
export async function capturePages(url, out, { max }) {
  log({ call: "capturePages", url, max });
  const site = JSON.parse(process.env.CREATIVE_VIDEO_FAKE_SITE ?? "{}")[url];
  if (!site) throw new Error(`net::ERR_NAME_NOT_RESOLVED at ${url}`);
  return {
    images: writeImages(out, site.pages.slice(0, max)),
    colors: site.colors,
    fonts: site.fonts,
  };
}

// CREATIVE_VIDEO_FAKE_FRAMES pages or frames (default 3), each the slide.
const frames = (out, max) =>
  writeImages(
    out,
    Array(Math.min(max, +(process.env.CREATIVE_VIDEO_FAKE_FRAMES ?? 3))).fill(
      SLIDE,
    ),
  );
export async function renderPdf(file, out, { max }) {
  log({ call: "renderPdf", file: path.basename(file), max });
  return frames(out, max);
}
export async function videoFrames(file, out, { max }) {
  log({ call: "videoFrames", file: path.basename(file), max });
  return frames(out, max);
}

// Every reference image the fake writes or a test hands in is a binary PPM
// already.
export async function ppm(file) {
  log({ call: "ppm", file: path.basename(file) });
  return fs.readFileSync(file);
}
