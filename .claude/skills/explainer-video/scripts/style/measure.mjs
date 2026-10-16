// Style extraction's first half: every source turned into reference images,
// and their colours measured into colour candidates a role can be assigned
// from.
//
//   node measure.mjs <run-folder> <source>...
//
// A source is a screenshot (.png, .jpg, .jpeg, .webp), a web page URL, a .pdf
// deck, a .pptx deck or a video (.mp4, .mov, .webm, .mkv). A page is captured
// with up to four same-site pages its navigation links, at 1440 by 900 with
// raster media hidden; a PDF's pages render in HyperFrames' Chrome; a video
// gives its scene-change frames; at most twelve images per source. A PPTX
// gives its theme's colours and fonts and no image. Colours a page or a theme
// declares count only where a measured colour candidate confirms them.
// stdout: `style ref <image>: <kind> · <source>` per reference image, then
//         `style candidate <id>: <hex> · <share>% · <images>` per colour
//         candidate, `style declared <hex>: not in the reference images,
//         dropped` per declared colour no colour candidate confirms, then
//         `style: measured <n> reference image(s) -> <candidates.json>`
// writes: <run>/style-draft/refs/ and candidates.json (both replaced whole),
//         and explainers/.gitignore
// exit:   0 measured · 1 a source refused or unreadable, `source <source>:
//         <why>` or a setup row's `style: <row> is not installed` on stderr,
//         and no candidates.json · 2 usage
import fs from "node:fs";
import path from "node:path";
import { writeIgnore } from "../lib/runfolder.mjs";
import { oklab } from "../lib/style.mjs";
import { catalogue, dest, hyperframesEnv, loadBackend } from "../lib/tools.mjs";

const args = process.argv.slice(2);
const run = args.shift();
const given = [...new Set(args)];
if (!run || !given.length) {
  console.error("usage: node measure.mjs <run-folder> <source>...");
  process.exit(2);
}

const MAX = 12;
const isUrl = (s) => /^https?:\/\//i.test(s);
const EXT = {
  ".png": "image",
  ".jpg": "image",
  ".jpeg": "image",
  ".webp": "image",
  ".pdf": "pdf",
  ".pptx": "pptx",
  ".mp4": "video",
  ".mov": "video",
  ".webm": "video",
  ".mkv": "video",
};
// The rows a kind captures with: Chrome for what renders, the npm install for
// puppeteer, pdf.js and the PPTX unzip.
const NEEDS = {
  page: ["npm", "chrome"],
  pdf: ["npm", "chrome"],
  pptx: ["npm"],
};

const errors = [];
const refuse = (source, why) => errors.push(`source ${source}: ${why}`);
const draft = path.join(run, "style-draft");
const refs = path.join(draft, "refs");
function stop() {
  for (const e of errors) console.error(e);
  fs.rmSync(path.join(draft, "candidates.json"), { force: true });
  process.exit(1);
}

function kindOf(s) {
  if (isUrl(s)) return URL.canParse(s) ? "page" : refuse(s, "not a valid URL");
  if (!fs.statSync(s, { throwIfNoEntry: false })?.isFile())
    return refuse(s, "no such file");
  return (
    EXT[path.extname(s).toLowerCase()] ??
    refuse(
      s,
      `cannot take ${path.extname(s) || "a file with no extension"}: give a web page URL or a file ending ${Object.keys(EXT).join(", ")}`,
    )
  );
}

const kinds = given.map(kindOf);
for (const k of new Set(kinds.flatMap((k) => NEEDS[k] ?? [])))
  for (const r of catalogue().filter((r) => r.kind === k))
    if (!fs.existsSync(path.join(dest(r), ".stamp")))
      errors.push(
        `style: ${r.id} is not installed: run /explainer-video setup`,
      );
if (errors.length) stop();

// Ids from each source's name, kebab-case, a repeat numbered.
const ids = new Set();
function idOf(s, kind) {
  const base =
    kind === "page"
      ? new URL(s).hostname.replace(/^www\./, "")
      : path.basename(s, path.extname(s));
  const slug =
    base
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "") || "source";
  let id = slug;
  for (let n = 2; ids.has(id); n++) id = `${slug}-${n}`;
  ids.add(id);
  return id;
}

// A PPTX theme's colour scheme and its heading and body fonts.
function theme(parts) {
  const xml =
    Object.entries(parts)
      .filter(([f]) => /^ppt\/theme\/theme\d+\.xml$/.test(f))
      .sort(([a], [b]) =>
        a.localeCompare(b, "en", { numeric: true }),
      )[0]?.[1] ?? "";
  const scheme = xml.match(/<a:clrScheme[\s\S]*?<\/a:clrScheme>/)?.[0] ?? "";
  const colors = [
    ...scheme.matchAll(
      /<a:(?:srgbClr val|sysClr [^>]*lastClr)="([0-9A-Fa-f]{6})"/g,
    ),
  ].map((m) => `#${m[1].toLowerCase()}`);
  const fonts = ["majorFont", "minorFont"]
    .map(
      (f) =>
        xml.match(
          new RegExp(`<a:${f}>[\\s\\S]*?<a:latin typeface="([^"]+)"`),
        )?.[1],
    )
    .filter(Boolean);
  return { colors, fonts };
}

fs.rmSync(refs, { recursive: true, force: true });
fs.mkdirSync(refs, { recursive: true });
writeIgnore(run);
const backend = await loadBackend();
const images = [];
const declared = [];
const fonts = [];
const report = [];
for (const [i, s] of given.entries()) {
  const kind = kinds[i];
  const id = idOf(s, kind);
  const before = errors.length;
  let files = [];
  try {
    if (kind === "image") {
      const to = path.join(refs, `${id}-1${path.extname(s).toLowerCase()}`);
      fs.copyFileSync(s, to);
      files = [to];
    } else if (kind === "pptx") {
      const t = theme(await backend.unzip(s));
      if (!t.colors.length) refuse(s, "no theme colours in the deck");
      declared.push(...t.colors);
      fonts.push(...t.fonts);
    } else {
      const out = path.join(refs, id);
      const opts = { env: hyperframesEnv(), max: MAX };
      if (kind === "pdf") files = await backend.renderPdf(s, out, opts);
      else if (kind === "video")
        files = await backend.videoFrames(s, out, opts);
      else {
        const site = await backend.capturePages(s, out, { ...opts, max: 5 });
        files = site.images;
        declared.push(...site.colors);
        fonts.push(...site.fonts);
      }
      if (!files.length) refuse(s, "gave no image");
    }
  } catch (e) {
    refuse(s, `could not capture it: ${e.message}`);
  }
  if (errors.length > before) continue;
  for (const f of files.slice(0, MAX)) {
    images.push({ name: path.basename(f), file: f, source: s });
    report.push(`style ref ${path.basename(f)}: ${kind} · ${s}`);
  }
}
if (!errors.length && !images.length)
  errors.push(
    "style: a deck's theme has no pixels to measure: export the deck to PDF and give the PDF beside it",
  );
if (errors.length) stop();

// A binary PPM's size and its RGB bytes, decoded once per image.
function decode(buf) {
  const m = buf
    .subarray(0, 64)
    .toString("latin1")
    .match(/^P6\s+(\d+)\s+(\d+)\s+255\s/);
  if (!m) throw new Error("not a binary PPM");
  return { w: +m[1], h: +m[2], px: buf.subarray(m[0].length) };
}
for (const img of images)
  try {
    img.pixels = decode(await backend.ppm(img.file));
  } catch (e) {
    refuse(img.source, `could not read ${img.name}: ${e.message}`);
  }
if (errors.length) stop();

// HLS saturation and lightness, as #664 measured them: a pixel counts toward
// an accent when saturated (S at least `floor`) and neither near black nor
// near white (L 0.15 to 0.85).
function saturated(r, g, b, floor) {
  const hi = Math.max(r, g, b) / 255;
  const lo = Math.min(r, g, b) / 255;
  const l = (hi + lo) / 2;
  if (l < 0.15 || l > 0.85 || hi === lo) return false;
  return (hi - lo) / (l <= 0.5 ? hi + lo : 2 - hi - lo) >= floor;
}

const hexOf = (k) => "#" + k.toString(16).padStart(6, "0");
// Per image, each 4-bit bucket's area share and the exact colours inside it,
// so every image weighs the same whatever its size.
function tally(floor) {
  const all = new Map();
  for (const img of images) {
    const { w, h, px } = img.pixels;
    const n = w * h;
    const mine = new Map();
    for (let o = 0; o < n * 3; o += 3) {
      const [r, g, b] = [px[o], px[o + 1], px[o + 2]];
      if (floor !== null && !saturated(r, g, b, floor)) continue;
      const key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      const exact = (r << 16) | (g << 8) | b;
      let e = mine.get(key);
      if (!e) mine.set(key, (e = { count: 0, exact: new Map() }));
      e.count++;
      e.exact.set(exact, (e.exact.get(exact) ?? 0) + 1);
    }
    for (const [key, e] of mine) {
      let a = all.get(key);
      if (!a) all.set(key, (a = { share: 0, images: [], exact: new Map() }));
      a.share += e.count / n / images.length;
      a.images.push({ name: img.name, share: e.count / n });
      for (const [x, c] of e.exact)
        a.exact.set(x, (a.exact.get(x) ?? 0) + c / n);
    }
  }
  return all;
}

// The buckets at or above `min` share, largest first, each named by its most
// common exact colour (a surface sample, never a blend) and the images it
// covers `min` of.
function rank(all, min, top, prefix) {
  return [...all.values()]
    .filter((a) => a.share >= min)
    .map((a) => {
      const [exact] = [...a.exact].sort(
        (x, y) => y[1] - x[1] || x[0] - y[0],
      )[0];
      return {
        hex: hexOf(exact),
        share: Math.round(a.share * 1e4) / 1e4,
        images: a.images.filter((i) => i.share >= min).map((i) => i.name),
      };
    })
    .sort((x, y) => y.share - x.share || x.hex.localeCompare(y.hex))
    .slice(0, top)
    .map((c, n) => ({ id: `${prefix}${n + 1}`, ...c }));
}

const surfaces = rank(tally(null), 0.005, 10, "s");
// A monochrome brand: the floor drops once before there are no accents.
let accents = rank(tally(0.4), 0.001, 8, "a");
if (!accents.length) accents = rank(tally(0.2), 0.001, 8, "a");

// How near a declared colour sits to a measured one, in OKLab.
const near = (a, b) => Math.hypot(...oklab(a).map((v, i) => v - oklab(b)[i]));

// A declared colour within 0.04 in OKLab of a colour candidate names it
// exactly; one no colour candidate confirms is dropped.
const dropped = [];
for (const hex of [...new Set(declared)]) {
  const hit = [...surfaces, ...accents]
    .filter((c) => near(c.hex, hex) <= 0.04)
    .sort((x, y) => near(x.hex, hex) - near(y.hex, hex))[0];
  if (!hit) {
    dropped.push(hex);
    continue;
  }
  const was = hit.hex;
  for (const c of [...surfaces, ...accents])
    if (c.hex === was) Object.assign(c, { hex, declared: true });
}

const out = path.join(draft, "candidates.json");
fs.writeFileSync(
  out,
  JSON.stringify(
    {
      sources: given.map((source, i) => ({ kind: kinds[i], source })),
      images: images.map(({ name, source }) => ({ name, source })),
      fonts: [...new Set(fonts)],
      surfaces,
      accents,
    },
    null,
    2,
  ) + "\n",
);
for (const l of report) console.log(l);
for (const c of [...surfaces, ...accents])
  console.log(
    `style candidate ${c.id}: ${c.hex} · ${Math.round(c.share * 1000) / 10}% · ${c.images.join(", ")}`,
  );
for (const hex of dropped)
  console.log(`style declared ${hex}: not in the reference images, dropped`);
console.log(`style: measured ${images.length} reference image(s) -> ${out}`);
