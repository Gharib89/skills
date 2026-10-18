// The backend's source readers.
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { skill, toolPaths, torchDevice } from "../tools.mjs";
import { fromCache, ffmpeg } from "./common.mjs";

// The source stage's readers, each one format to text or HTML; the stage turns
// HTML to Markdown through toMarkdown and splits each snapshot by locator.

// A web page (or a local HTML file, by its file: URL) as it reads once its
// scripts have run: loaded in HyperFrames' Chrome until the network is idle,
// then Readability, run inside the page, keeps the article. A page Readability
// finds no article in keeps its whole body.
export async function renderPage(url, { env }) {
  const req = fromCache(toolPaths().node);
  const browser = await sandboxed(env);
  try {
    const page = await browser.newPage();
    // The page's own CSP would block the injected Readability script.
    await page.setBypassCSP(true);
    // A page that never goes idle (a poll, a stream) is read as it stands.
    const res = await page
      .goto(url, { waitUntil: "networkidle0", timeout: 30000 })
      .catch((e) => {
        if (e.name !== "TimeoutError") throw e;
      });
    if (res && !res.ok()) throw new Error(`HTTP ${res.status()} at ${url}`);
    await page.addScriptTag({
      path: req.resolve("@mozilla/readability/Readability.js"),
    });
    return await page.evaluate(() => {
      const a = new window.Readability(document.cloneNode(true)).parse();
      return a?.content
        ? {
            title: a.title || document.title,
            html: a.content,
            text: a.textContent,
          }
        : {
            title: document.title,
            html: document.body?.innerHTML ?? "",
            text: document.body?.innerText ?? "",
          };
    });
  } finally {
    await browser.close();
  }
}

// A page from the internet, or a file the user hands in, gets Chrome's sandbox
// where it starts; it does not where the kernel bars unprivileged user
// namespaces (Ubuntu's AppArmor default) or as root, and there it runs
// unsandboxed.
function sandboxed(env) {
  const launch = (args) =>
    fromCache(toolPaths().node)("puppeteer-core").launch({
      headless: true,
      executablePath: findChrome(env.HOME),
      args,
    });
  return launch([]).catch(() => launch(["--no-sandbox"]));
}

// Style extraction's reference images, each written as `<out>-<n>.png`.

// A page and the same-site pages its navigation links, `max` in all, each
// captured at 1440 by 900 in the site's default colour scheme with raster
// media hidden (images, video, canvas, frames and every CSS background image),
// so hero art never reads as the brand; inline SVG and text stay. With them,
// the colours the visible elements declare and the families the body and
// headings name.
export async function capturePages(url, out, { env, max }) {
  const browser = await sandboxed(env);
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1440, height: 900 });
    const images = [];
    const colors = new Set();
    const fonts = [];
    const queue = [url];
    const seen = new Set();
    while (queue.length && images.length < max) {
      const u = queue.shift();
      if (seen.has(u)) continue;
      seen.add(u);
      // A page that never goes idle (a poll, a stream) is taken as it stands.
      // A linked page that fails (a dead link, a PDF) is skipped; only the
      // start page refuses the site.
      let failed;
      const res = await page
        .goto(u, { waitUntil: "networkidle0", timeout: 30000 })
        .catch((e) => {
          if (e.name !== "TimeoutError") failed = e;
        });
      if (failed || (res && !res.ok())) {
        if (u === url)
          throw failed ?? new Error(`HTTP ${res.status()} at ${u}`);
        continue;
      }
      const found = await page.evaluate(() => {
        const hide = document.createElement("style");
        hide.textContent =
          "img,picture,video,canvas,iframe,embed,object,svg image{visibility:hidden!important}*,*::before,*::after{background-image:none!important}";
        document.head.append(hide);
        // A computed colour keeps its own syntax (oklch, lab, color()), so
        // each is painted on a 1x1 canvas and read back as the sRGB pixel.
        const ctx = Object.assign(document.createElement("canvas"), {
          width: 1,
          height: 1,
        }).getContext("2d", { willReadFrequently: true });
        const hex = (c) => {
          ctx.clearRect(0, 0, 1, 1);
          ctx.fillStyle = "transparent";
          ctx.fillStyle = c;
          ctx.fillRect(0, 0, 1, 1);
          const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;
          if (a === 0) return null;
          return (
            "#" + [r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")
          );
        };
        const colors = [];
        for (const el of document.querySelectorAll("body, body *")) {
          if (!el.checkVisibility()) continue;
          const cs = getComputedStyle(el);
          const own = [cs.color, cs.backgroundColor];
          if (parseFloat(cs.borderTopWidth) > 0) own.push(cs.borderTopColor);
          for (const c of own) if (hex(c)) colors.push(hex(c));
        }
        const stack = (el, role) =>
          el && { role, stack: getComputedStyle(el).fontFamily };
        const links = [
          ...document.querySelectorAll("nav a[href], header a[href]"),
        ]
          .map((a) => new URL(a.href, location.href))
          .filter((l) => l.origin === location.origin)
          .map((l) => l.origin + l.pathname + l.search);
        return {
          colors,
          fonts: [
            stack(document.body, "text"),
            stack(document.querySelector("h1, h2"), "title"),
          ].filter(Boolean),
          links,
        };
      });
      const f = `${out}-${images.length + 1}.png`;
      await page.screenshot({ path: f });
      images.push(f);
      found.colors.forEach((c) => colors.add(c));
      fonts.push(...found.fonts);
      if (u === url) queue.push(...found.links);
    }
    return { images, colors: [...colors], fonts };
  } finally {
    await browser.close();
  }
}

// `max` of the `n` pages or frames, spread evenly from the first to the last.
const spread = (n, max) =>
  n <= max
    ? [...Array(n).keys()]
    : [...Array(max).keys()].map((i) => Math.round((i * (n - 1)) / (max - 1)));

// A PDF's pages rendered 1440 wide by pdf.js inside HyperFrames' Chrome, `max`
// of them spread through the deck. pdf.js and the PDF are served to the page
// over loopback, since Chrome loads no module from a file: URL.
export async function renderPdf(file, out, { env, max }) {
  const build = path.join(
    toolPaths().node,
    "node_modules",
    "pdfjs-dist",
    "build",
  );
  const served = {
    "/pdf.mjs": path.join(build, "pdf.mjs"),
    "/pdf.worker.mjs": path.join(build, "pdf.worker.mjs"),
    "/doc.pdf": path.resolve(file),
  };
  const server = http.createServer((req, res) => {
    if (req.url === "/")
      return res
        .writeHead(200, { "content-type": "text/html" })
        .end("<!doctype html><body></body>");
    const f = served[req.url];
    if (!f) return res.writeHead(404).end();
    res
      .writeHead(200, {
        "content-type": f.endsWith(".pdf")
          ? "application/pdf"
          : "text/javascript",
      })
      .end(fs.readFileSync(f));
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  let browser;
  try {
    browser = await sandboxed(env);
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const count = await page.evaluate(async () => {
      const pdfjs = await import("/pdf.mjs");
      pdfjs.GlobalWorkerOptions.workerSrc = "/pdf.worker.mjs";
      window.doc = await pdfjs.getDocument({ url: "/doc.pdf" }).promise;
      return window.doc.numPages;
    });
    const images = [];
    for (const n of spread(count, max)) {
      const url = await page.evaluate(async (n) => {
        const p = await window.doc.getPage(n);
        const viewport = p.getViewport({
          scale: 1440 / p.getViewport({ scale: 1 }).width,
        });
        const canvas = document.createElement("canvas");
        canvas.width = Math.round(viewport.width);
        canvas.height = Math.round(viewport.height);
        await p.render({ canvas, viewport }).promise;
        return canvas.toDataURL("image/png");
      }, n + 1);
      const f = `${out}-${images.length + 1}.png`;
      fs.writeFileSync(f, Buffer.from(url.split(",")[1], "base64"));
      images.push(f);
    }
    return images;
  } finally {
    await browser?.close();
    server.close();
  }
}

// A video's first frame, its scene changes and its last frame, 1440 wide,
// `max` of them spread through the video.
export async function videoFrames(file, out, { max }) {
  const tmp = `${out}.frames`;
  fs.mkdirSync(tmp, { recursive: true });
  try {
    ffmpeg([
      ...["-i", file, "-vf", "select='eq(n,0)+gt(scene,0.3)',scale=1440:-2"],
      ...["-fps_mode", "vfr", path.join(tmp, "%04d.png")],
    ]);
    ffmpeg([
      ...["-sseof", "-1", "-i", file, "-vf", "scale=1440:-2"],
      ...["-update", "1", path.join(tmp, "9999.png")],
    ]);
    const all = fs.readdirSync(tmp).sort();
    return spread(all.length, max).map((i, n) => {
      const f = `${out}-${n + 1}.png`;
      fs.renameSync(path.join(tmp, all[i]), f);
      return f;
    });
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

// An image decoded to a binary PPM at most 480 wide, each pixel a colour the
// image holds (nearest-neighbour scaling, never a blend).
export async function ppm(file) {
  const r = spawnSync(
    "ffmpeg",
    [
      ...["-hide_banner", "-v", "error", "-i", file, "-frames:v", "1"],
      ...["-vf", "scale='min(480,iw)':-2:flags=neighbor"],
      ...["-f", "image2pipe", "-vcodec", "ppm", "-"],
    ],
    { maxBuffer: 1 << 28 },
  );
  if (r.status !== 0)
    throw new Error(
      `ffmpeg could not decode ${file}: ${(r.stderr?.toString() || r.error?.message || "").trim().split("\n").pop()}`,
    );
  return r.stdout;
}

// HTML to Markdown, headings as `#` lines, with Turndown's Markdown escaping
// off: a snapshot is read and quoted word for word, never rendered.
export async function toMarkdown(html) {
  const Turndown = fromCache(toolPaths().node)("turndown");
  const td = new Turndown({
    headingStyle: "atx",
    codeBlockStyle: "fenced",
    bulletListMarker: "-",
  });
  td.escape = (s) => s;
  return td.turndown(html);
}

// A PDF's text, one string per page, a line break where pdf.js marks one.
export async function pdfPages(file) {
  const entry = fromCache(toolPaths().node).resolve(
    "pdfjs-dist/legacy/build/pdf.mjs",
  );
  const pdfjs = await import(pathToFileURL(entry).href);
  const task = pdfjs.getDocument({
    data: new Uint8Array(fs.readFileSync(file)),
    isEvalSupported: false,
    verbosity: 0,
  });
  const doc = await task.promise;
  const pages = [];
  for (let n = 1; n <= doc.numPages; n++) {
    const { items } = await (await doc.getPage(n)).getTextContent();
    pages.push(items.map((i) => i.str + (i.hasEOL ? "\n" : "")).join(""));
  }
  await task.destroy();
  return pages;
}

// A DOCX as HTML, Word's heading styles as h1 to h6.
export async function docxHtml(file) {
  const mammoth = fromCache(toolPaths().node)("mammoth");
  return (await mammoth.convertToHtml({ path: file })).value;
}

// A zip's XML parts and their .rels by path, as text; a PPTX's media stays
// unread.
export async function unzip(file) {
  const JSZip = fromCache(toolPaths().node)("jszip");
  const zip = await JSZip.loadAsync(fs.readFileSync(file));
  const out = {};
  for (const f of Object.values(zip.files))
    if (!f.dir && /\.(xml|rels)$/.test(f.name))
      out[f.name] = await f.async("string");
  return out;
}

// A code frame's Shiki tokens, one array per line, each `{ text, color }` with
// `color` a `var(--code-...)` the composition sets from the style profile.
let shiki;
export async function highlight(code, lang) {
  if (!shiki) {
    const req = fromCache(toolPaths().node);
    const [{ codeToTokens }, { createCssVariablesTheme }] = await Promise.all(
      ["shiki", "shiki/core"].map(
        (m) => import(pathToFileURL(req.resolve(m)).href),
      ),
    );
    const theme = createCssVariablesTheme({
      name: "profile",
      variablePrefix: "--code-",
      fontStyle: false,
    });
    shiki = (c, l) => codeToTokens(c, { lang: l, theme });
  }
  const { tokens } = await shiki(code, lang);
  return tokens.map((line) =>
    line.map((t) => ({ text: t.content, color: t.color })),
  );
}

// rough.js outlines, each shape `{ rect: [w, h] }` or `{ line: [[x, y], ...] }`
// at its `seed`, as SVG path data: `fill` a rect's body, `stroke` its outline.
// A rect sits 3 px inside its box so the wobble stays in view.
let rough;
export async function sketch(shapes) {
  if (!rough) {
    const m = fromCache(toolPaths().node)("roughjs");
    rough = (m.default ?? m).generator();
  }
  return shapes.map(({ rect, line, seed }) => {
    const paths = rough.toPaths(
      rect
        ? rough.rectangle(3, 3, rect[0] - 6, rect[1] - 6, {
            seed,
            fill: "#000",
            fillStyle: "solid",
          })
        : rough.linearPath(line, { seed }),
    );
    const d = (k) =>
      paths
        .filter((p) => p[k] !== "none")
        .map((p) => p.d)
        .join(" ");
    return { fill: d("fill"), stroke: d("stroke") };
  });
}
