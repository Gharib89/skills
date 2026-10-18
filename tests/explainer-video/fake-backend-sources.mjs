// Canned source readers: fixture PDF, PPTX and DOCX files and rendered pages.
import fs from "node:fs";
import path from "node:path";
import { log } from "./fake-backend-log.mjs";

// The source readers. A fixture .pdf holds `{"pages": [...]}` and a .pptx
// `{"parts": {path: xml}}`, both JSON; a .docx holds the HTML mammoth would
// give. renderPage answers a URL from the JSON map in
// $EXPLAINER_VIDEO_FAKE_PAGES ({url: {title, html}}), a file: URL from the
// file, as the page Chrome would hand Readability once its scripts ran; its
// text is the HTML without its tags.
export async function renderPage(url) {
  log({ call: "renderPage", url });
  const text = (html) => html.replace(/<[^>]+>/g, "");
  if (url.startsWith("file:")) {
    const file = fs.readFileSync(new URL(url), "utf8");
    const html = file.replace(/^[\s\S]*<body>|<\/body>[\s\S]*$/g, "");
    return {
      title: file.match(/<title>([^<]*)<\/title>/)?.[1] ?? "",
      html,
      text: text(html),
    };
  }
  const page = JSON.parse(process.env.EXPLAINER_VIDEO_FAKE_PAGES ?? "{}")[url];
  if (!page) throw new Error(`net::ERR_NAME_NOT_RESOLVED at ${url}`);
  return { ...page, text: text(page.html) };
}

// Headings to `#` lines, each block its own paragraph, other tags dropped.
export async function toMarkdown(html) {
  return html
    .replace(
      /<h([1-6])>([\s\S]*?)<\/h\1>/g,
      (_, n, t) => `\n\n${"#".repeat(n)} ${t}\n\n`,
    )
    .replace(/<\/(p|li|div)>/g, "\n\n")
    .replace(/<[^>]+>/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export async function pdfPages(file) {
  log({ call: "pdfPages", file });
  return JSON.parse(fs.readFileSync(file, "utf8")).pages;
}

export async function docxHtml(file) {
  return fs.readFileSync(file, "utf8");
}

export async function unzip(file) {
  return JSON.parse(fs.readFileSync(file, "utf8")).parts;
}

// Each line's first word a keyword, the rest plain.
export async function highlight(code, lang) {
  log({ call: "highlight", lang });
  return code.split("\n").map((l) => {
    const [, word, rest] = l.match(/^(\S*)(.*)$/);
    return [
      { text: word, color: "var(--code-token-keyword)" },
      { text: rest, color: "var(--code-foreground)" },
    ].filter((t) => t.text);
  });
}

// Path data that spells each shape's size and seed.
export async function sketch(shapes) {
  log({ call: "sketch", shapes });
  return shapes.map((s) => ({
    fill: s.rect ? `M0 0 H${s.rect[0]} V${s.rect[1]} H0 Z` : "",
    stroke: `M0 0 L${s.seed % 997} ${s.rect?.[1] ?? 40}`,
  }));
}

// Style extraction's decode: every reference image the fake writes or a test
// hands in is a binary PPM already.
export async function ppm(file) {
  log({ call: "ppm", file: path.basename(file) });
  return fs.readFileSync(file);
}

// A binary PPM 50 wide, filled top to bottom by the bands, each `[hex, rows]`:
// the fake's every captured page, PDF page and video frame, written under the
// `.png` name the real capture gives it.
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

// EXPLAINER_VIDEO_FAKE_SITE maps a URL to `{ pages, colors, fonts }`, each
// page a list of bands.
export async function capturePages(url, out, { max }) {
  log({ call: "capturePages", url, max });
  const site = JSON.parse(process.env.EXPLAINER_VIDEO_FAKE_SITE ?? "{}")[url];
  if (!site) throw new Error(`net::ERR_NAME_NOT_RESOLVED at ${url}`);
  return {
    images: writeImages(out, site.pages.slice(0, max)),
    colors: site.colors,
    fonts: site.fonts,
  };
}

// EXPLAINER_VIDEO_FAKE_FRAMES pages or frames (default 3), each the slide.
const frames = (out, max) =>
  writeImages(
    out,
    Array(Math.min(max, +(process.env.EXPLAINER_VIDEO_FAKE_FRAMES ?? 3))).fill(
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
