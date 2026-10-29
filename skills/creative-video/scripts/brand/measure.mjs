// The brand stage's `measure`: every source turned into reference images, and
// their colours measured into the candidates a brand's colours are taken from
// (`brand.mjs <run> measure <source>...`, forked from explainer-video's style
// measure).
//
// A source is a screenshot (.png, .jpg, .jpeg, .webp), a web page URL, a .pdf,
// a .pptx deck or a video (.mp4, .mov, .webm, .mkv). A page is captured with
// up to four same-site pages its navigation links, 1440 wide and down to 5400
// px, with raster media hidden; a PDF's pages render in HyperFrames' Chrome; a
// video gives its first, scene-change and last frames; at most twelve images
// per source. A PPTX gives its theme's colours and fonts and no image. Each
// image weighs the same whatever its size, so every page counts. Colours a page
// declares count only where a candidate its own images show confirms them, and
// a PPTX theme's only where its exported PDF's pages do.
// stdout: `brand ref <image>: <kind> · <source>` per reference image, then
//         `brand candidate <id>: <hex> · <share>% · <images>` per candidate,
//         `brand declared <hex>: not in the reference images, dropped` per
//         declared colour no candidate confirms (`its candidate is <hex>
//         already, dropped` when another named it first), `brand font <role>:
//         <family>` per declared family, then `brand: measured <n> reference image(s) ->
//         <candidates.json>`
// writes: <run>/brand/refs/ and brand/candidates.json (both replaced whole),
//         and the runs folder's .gitignore
// refuses: `source <source>: <why>`, or a setup row's `<row> is not installed:
//         run /creative-video setup`, each line after the stage's `brand: `,
//         with no candidates.json
import fs from "node:fs";
import path from "node:path";
import { writeIgnore } from "../lib/runfolder.mjs";
import { catalogue, dest, hyperframesEnv } from "../lib/tools.mjs";

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
// The setup rows a kind captures with: Chrome for what renders, the npm
// install for puppeteer, pdf.js and the PPTX unzip, ffmpeg for every image
// decoded and video frame cut.
const NEEDS = {
  image: ["ffmpeg"],
  page: ["npm-packages", "chrome", "ffmpeg"],
  pdf: ["npm-packages", "chrome", "ffmpeg"],
  pptx: ["npm-packages"],
  video: ["ffmpeg"],
};

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
  const fonts = [
    ["majorFont", "title"],
    ["minorFont", "text"],
  ]
    .map(([f, role]) => ({
      role,
      stack: xml.match(
        new RegExp(`<a:${f}>[\\s\\S]*?<a:latin typeface="([^"]+)"`),
      )?.[1],
    }))
    .filter((f) => f.stack);
  return { colors, fonts };
}

// The CSS generic families a font stack can fall back to.
const GENERIC = [
  "serif",
  "sans-serif",
  "monospace",
  "cursive",
  "fantasy",
  "system-ui",
  "ui-serif",
  "ui-sans-serif",
  "ui-monospace",
  "ui-rounded",
];
// A declared stack's first family and the generic it falls back to; a stack
// whose first entry is a generic names no family.
function declaredFont({ role, stack }) {
  const names = stack
    .split(",")
    .map((n) => n.replace(/["']/g, "").trim())
    .filter(Boolean);
  if (!names.length || GENERIC.includes(names[0])) return null;
  const generic = names.find((n) => GENERIC.includes(n));
  return { family: names[0], role, ...(generic && { generic }) };
}

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
function tally(images, floor) {
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

// A binary PPM's size and its RGB bytes.
function decodePpm(buf) {
  const m = buf
    .subarray(0, 64)
    .toString("latin1")
    .match(/^P6\s+(\d+)\s+(\d+)\s+255\s/);
  if (!m) throw new Error("not a binary PPM");
  return { w: +m[1], h: +m[2], px: buf.subarray(m[0].length) };
}

// OKLab (Björn Ottosson's), where a declared colour is compared with a
// measured one: `[L, a, b]` from a #rrggbb.
function oklab(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  const [l, m, s] = [
    0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
    0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
    0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
  ].map(Math.cbrt);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

// How near a declared colour sits to a measured one, in OKLab.
const near = (a, b) => Math.hypot(...oklab(a).map((v, i) => v - oklab(b)[i]));

export async function measure(run, given, backend) {
  const errors = [];
  const refuse = (source, why) => {
    errors.push(`source ${source}: ${why}`);
  };
  const draft = path.join(run, "brand");
  const refs = path.join(draft, "refs");
  const stop = () => {
    fs.rmSync(path.join(draft, "candidates.json"), { force: true });
    throw new Error(errors.join("\nbrand: "));
  };

  const kindOf = (s) => {
    if (isUrl(s))
      return URL.canParse(s) ? "page" : refuse(s, "not a valid URL");
    if (!fs.statSync(s, { throwIfNoEntry: false })?.isFile())
      return refuse(s, "no such file");
    return (
      EXT[path.extname(s).toLowerCase()] ??
      refuse(
        s,
        `cannot take ${path.extname(s) || "a file with no extension"}: give a web page URL or a file ending ${Object.keys(EXT).join(", ")}`,
      )
    );
  };
  const kinds = given.map(kindOf);
  for (const r of catalogue().filter((r) =>
    kinds.some((k) => NEEDS[k]?.includes(r.id)),
  ))
    if (
      r.kind === "system"
        ? !backend.which(r.command)
        : !fs.existsSync(path.join(dest(r), ".stamp"))
    )
      errors.push(`${r.id} is not installed: run /creative-video setup`);
  if (errors.length) stop();

  // Ids from each source's name, kebab-case, a repeat numbered.
  const ids = new Set();
  const idOf = (s, kind) => {
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
  };

  fs.rmSync(refs, { recursive: true, force: true });
  fs.mkdirSync(refs, { recursive: true });
  writeIgnore(run);
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
        declared.push(...t.colors.map((hex) => ({ hex, kind, source: s })));
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
          declared.push(
            ...site.colors.map((hex) => ({ hex, kind, source: s })),
          );
          fonts.push(...site.fonts);
        }
        if (!files.length) refuse(s, "gave no image");
      }
    } catch (e) {
      refuse(s, `could not capture it: ${e.message}`);
    }
    if (errors.length > before) continue;
    for (const f of files.slice(0, MAX)) {
      images.push({ name: path.basename(f), file: f, kind, source: s });
      report.push(`brand ref ${path.basename(f)}: ${kind} · ${s}`);
    }
  }
  if (!errors.length && !images.length)
    errors.push(
      "a deck's theme has no pixels to measure: export the deck to PDF and give the PDF beside it",
    );
  if (errors.length) stop();

  // Each image decoded once.
  for (const img of images)
    try {
      img.pixels = decodePpm(await backend.ppm(img.file));
    } catch (e) {
      refuse(img.source, `could not read ${img.name}: ${e.message}`);
    }
  if (errors.length) stop();

  const surfaces = rank(tally(images, null), 0.005, 10, "s");
  // A monochrome brand: the saturation floor drops once, and only then are
  // there no accents.
  let accents = rank(tally(images, 0.4), 0.001, 8, "a");
  if (!accents.length) accents = rank(tally(images, 0.2), 0.001, 8, "a");

  // The reference images that may confirm a declaration: a page's own, and a
  // PPTX theme's exported PDF pages.
  const shownBy = (d) =>
    new Set(
      images
        .filter((i) =>
          d.kind === "pptx" ? i.kind === "pdf" : i.source === d.source,
        )
        .map((i) => i.name),
    );

  // A declared colour within 0.04 in OKLab of a candidate those images show
  // names it exactly; one no such candidate confirms is dropped, and so is one
  // whose nearest candidate another declared colour named first.
  const confirmed = new Set();
  const dropped = new Map();
  for (const { hex, ...d } of declared) {
    const by = shownBy(d);
    const hit = [...surfaces, ...accents]
      .filter(
        (c) => c.images.some((i) => by.has(i)) && near(c.hex, hex) <= 0.04,
      )
      .sort((x, y) => near(x.hex, hex) - near(y.hex, hex))[0];
    if (!hit) {
      dropped.set(hex, "not in the reference images");
      continue;
    }
    if (hit.declared && hit.hex !== hex) {
      dropped.set(hex, `its candidate is ${hit.hex} already`);
      continue;
    }
    confirmed.add(hex);
    const was = hit.hex;
    for (const c of [...surfaces, ...accents])
      if (c.hex === was) Object.assign(c, { hex, declared: true });
  }
  for (const hex of confirmed) dropped.delete(hex);

  const families = [
    ...new Map(
      fonts
        .map(declaredFont)
        .filter(Boolean)
        .map((f) => [`${f.role} ${f.family}`, f]),
    ).values(),
  ];
  const out = path.join(draft, "candidates.json");
  fs.writeFileSync(
    out,
    JSON.stringify(
      {
        sources: given.map((source, i) => ({ kind: kinds[i], source })),
        images: images.map(({ name, source }) => ({ name, source })),
        fonts: families,
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
      `brand candidate ${c.id}: ${c.hex} · ${Math.round(c.share * 1000) / 10}% · ${c.images.join(", ")}`,
    );
  for (const [hex, why] of dropped)
    console.log(`brand declared ${hex}: ${why}, dropped`);
  for (const f of families) console.log(`brand font ${f.role}: ${f.family}`);
  console.log(`brand: measured ${images.length} reference image(s) -> ${out}`);
}
