// The backend's brand readers: the reference images a brand is measured from,
// each written as `<out>-<n>.png`.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { toolPaths } from "../tools.mjs";
import { ffmpeg } from "./common.mjs";
import { sandboxed } from "./source.mjs";

// A page and the same-site pages its navigation links, `max` in all, each
// captured 1440 wide in the site's default colour scheme with raster media
// hidden (images, video, canvas, frames and every CSS background image), so
// hero art never reads as the brand; inline SVG and text stay. Each screenshot
// covers the page down to at most 5400 px, not the 900 px viewport, so the
// colours are measured by area across the page and not by the hero alone. With
// the images, the colours the visible elements declare and the families the
// body and headings name.
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
          height: document.documentElement.scrollHeight,
          fonts: [
            stack(document.body, "text"),
            stack(document.querySelector("h1, h2"), "title"),
          ].filter(Boolean),
          links,
        };
      });
      const f = `${out}-${images.length + 1}.png`;
      await page.screenshot({
        path: f,
        captureBeyondViewport: true,
        clip: { x: 0, y: 0, width: 1440, height: Math.min(found.height, 5400) },
      });
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
