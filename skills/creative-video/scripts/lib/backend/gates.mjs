// The backend's gate measures: HyperFrames' check and snapshot, the text probe
// and a frame's pixels.
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { HEIGHT, WIDTH } from "../../render/root.mjs";
import { toolPaths } from "../tools.mjs";
import { cliPath, findChrome } from "./browser.mjs";
import { fromCache } from "./common.mjs";

// The pinned CLI run in the project with its output captured.
function captured(args, { dir, env }) {
  return spawnSync(process.execPath, [cliPath(), ...args], {
    cwd: dir,
    env,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 1 << 26,
  });
}
const failed = (what, r) =>
  new Error(
    `hyperframes ${what} exited ${r.status ?? r.signal}: ${(r.stderr || r.error?.message || "").trim().split("\n")[0]}`,
  );

// `hyperframes check` on the frames at `times` (video seconds): its JSON report,
// which it prints on exit 0 (clean) and exit 1 (findings) alike.
export async function check(dir, times, { env }) {
  const r = captured(["check", "--json", "--at", times.join(",")], {
    dir,
    env,
  });
  if (r.status !== 0 && r.status !== 1) throw failed("check", r);
  try {
    return JSON.parse(r.stdout);
  } catch {
    throw failed("check", r);
  }
}

// `hyperframes snapshot` of the frames at `times` into `outDir`, one browser
// launch for all: `[{ path, time }]`. The CLI prints progress, then its report
// as a JSON object that starts on a line of its own.
export async function snapshot(dir, times, outDir, { env }) {
  const args = ["snapshot", "--at", times.join(","), "--no-end"];
  const r = captured(
    [...args, "--no-browser-gpu", "--json", "-o", path.resolve(outDir)],
    { dir, env },
  );
  const from = r.stdout.search(/^\{$/m);
  const to = r.stdout.indexOf("\n}", from);
  let report;
  try {
    report = JSON.parse(r.stdout.slice(from, to + 2));
  } catch {
    throw failed("snapshot", r);
  }
  if (r.status !== 0 || !report.ok) throw failed("snapshot", r);
  return report.frames.map(({ path, time }) => ({ path, time }));
}

// The SHA-256 of an image's decoded pixels (RGB at full size), never of its
// file, so encoder metadata can neither pass nor fail a comparison.
export async function framePixels(file) {
  const r = spawnSync(
    "ffmpeg",
    [
      ...["-hide_banner", "-v", "error", "-i", file, "-frames:v", "1"],
      ...["-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
    ],
    { maxBuffer: 1 << 28 },
  );
  if (r.status !== 0)
    throw new Error(
      `ffmpeg could not decode ${file}: ${(r.stderr?.toString() || r.error?.message || "").trim().split("\n").pop()}`,
    );
  return crypto.createHash("sha256").update(r.stdout).digest("hex");
}

const MIME = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".wav": "audio/wav",
  ".mp3": "audio/mpeg",
  ".woff2": "font/woff2",
  ".woff": "font/woff",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".gif": "image/gif",
  ".mp4": "video/mp4",
  ".webm": "video/webm",
};

// The project open in a fresh browser, ready to seek. It is served as
// `hyperframes check` sees it: its folder over HTTP with the HyperFrames
// runtime injected into index.html, which mounts the data-composition-src scenes
// and sets window.__renderReady.
async function open(dir, env) {
  const nodeDir = toolPaths().node;
  const runtime = path.join(
    nodeDir,
    "node_modules",
    "hyperframes",
    "dist",
    "hyperframe.runtime.iife.js",
  );
  const root = path.resolve(dir);
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split("?")[0]);
    const file =
      url === "/__hf_runtime.js"
        ? runtime
        : path.join(root, url === "/" ? "index.html" : url);
    const ok =
      (file === runtime || file.startsWith(root + path.sep)) &&
      fs.statSync(file, { throwIfNoEntry: false })?.isFile();
    if (!ok) return res.writeHead(404).end();
    const body = fs.readFileSync(file);
    res.writeHead(200, {
      "content-type": MIME[path.extname(file)] ?? "application/octet-stream",
    });
    res.end(
      file === path.join(root, "index.html")
        ? body
            .toString()
            .replace(
              /<\/body>/i,
              '<script src="/__hf_runtime.js"></script></body>',
            )
        : body,
    );
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  let browser;
  const close = async () => {
    await browser?.close();
    server.close();
  };
  try {
    browser = await fromCache(nodeDir)("puppeteer-core").launch({
      headless: true,
      executablePath: findChrome(env.HOME),
      args: ["--no-sandbox", "--font-render-hinting=none"],
    });
    const page = await browser.newPage();
    await page.setViewport({ width: WIDTH, height: HEIGHT });
    await page.goto(`http://127.0.0.1:${server.address().port}/`, {
      waitUntil: "domcontentloaded",
    });
    const ready = await page
      .waitForFunction(
        () =>
          window.__renderReady || typeof window.__hfStartupError === "string",
        { timeout: 10000 },
      )
      .then(() => true)
      .catch(() => false);
    const startup = await page.evaluate(() => window.__hfStartupError);
    if (typeof startup === "string")
      throw new Error(`composition startup error: ${startup}`);
    if (!ready) throw new Error("composition not render-ready within 10 s");
    return { page, close };
  } catch (e) {
    await close();
    throw e;
  }
}

// The page seeked to `t` and settled: fonts loaded, two frames painted.
function seek(page, t) {
  return page.evaluate(async (t) => {
    // The seek targets `hyperframes check` tries, in its order.
    const { __player: p, __hf: hf, __timelines: tls, gsap } = window;
    if (p?.renderSeek) p.renderSeek(t);
    else if (hf?.seek) hf.seek(t);
    else if (p?.seek) p.seek(t);
    else
      for (const tl of Object.values(tls ?? {})) {
        tl.pause();
        tl.seek(t);
      }
    gsap?.ticker?.tick();
    await window.__hfWaitForSeekCompletion?.();
    await document.fonts.ready;
    await new Promise((r) =>
      requestAnimationFrame(() => requestAnimationFrame(r)),
    );
    await new Promise((r) => setTimeout(r, 120));
  }, t);
}

// Runs in the page for one frame: every visible element with text of its own,
// measured and unjudged. `opacity` is the product up its ancestors.
function measureFrame() {
  const r1 = (n) => Math.round(n * 10) / 10;
  const sub = '[data-composition-id]:not([data-composition-id="main"])';
  const out = [];
  for (const el of document.querySelectorAll("#root *")) {
    const texts = [...el.childNodes].filter(
      (n) => n.nodeType === 3 && n.textContent.trim(),
    );
    const own = texts.map((n) => n.textContent.trim()).join(" ");
    if (
      !own ||
      !el.checkVisibility({ visibilityProperty: true }) ||
      el.closest("[data-layout-ignore]")
    )
      continue;
    const r = el.getBoundingClientRect();
    // Where the glyphs are: a block's box spans its container wherever its
    // text sits, so the rect is the union of its own text nodes' boxes.
    const glyphs = texts.map((n) => {
      const range = document.createRange();
      range.selectNodeContents(n);
      return range.getBoundingClientRect();
    });
    let opacity = 1;
    for (let a = el; a; a = a.parentElement)
      opacity *= +getComputedStyle(a).opacity;
    const scale = el.offsetHeight > 0 ? r.height / el.offsetHeight : 1;
    out.push({
      text: own,
      words: own.split(/\s+/).length,
      scene: el.closest(sub)?.dataset.compositionId ?? null,
      rect: {
        left: r1(Math.min(...glyphs.map((g) => g.left))),
        top: r1(Math.min(...glyphs.map((g) => g.top))),
        right: r1(Math.max(...glyphs.map((g) => g.right))),
        bottom: r1(Math.max(...glyphs.map((g) => g.bottom))),
      },
      fontPx: parseFloat(getComputedStyle(el).fontSize) * scale,
      opacity,
    });
  }
  return out;
}

// Runs in the page: each scene's tween windows, in the scene's own seconds, and
// its sounds as `{ id, start, authored }` (gates/sounds.mjs): the live
// data-start, and the data-start its scene file gives the <audio> with that id
// before any script runs, null where the file has none.
async function sceneEvents() {
  const r3 = (n) => Math.round(n * 1000) / 1000;
  const out = {};
  for (const [id, tl] of Object.entries(window.__timelines ?? {})) {
    if (id === "main" || id === "captions") continue;
    // startTime() and endTime() are in the parent's time: lift a nested
    // tween's through each ancestor's start to the scene timeline's.
    const lift = (c, t) => {
      for (let p = c.parent; p && p !== tl; p = p.parent)
        t = p.startTime() + t / p.timeScale();
      return r3(t);
    };
    const host = document.querySelector(
      `[data-composition-id="${id}"][data-composition-src]`,
    );
    const authored = new Map();
    if (host) {
      // Unread, every static <audio> would pass as a created one.
      const res = await fetch(host.dataset.compositionSrc);
      if (!res.ok)
        throw new Error(`${host.dataset.compositionSrc}: HTTP ${res.status}`);
      const file = new DOMParser().parseFromString(
        await res.text(),
        "text/html",
      );
      for (const a of (
        file.querySelector("template")?.content ?? file
      ).querySelectorAll("audio[id]"))
        authored.set(a.id, r3(+(a.getAttribute("data-start") ?? 0)));
    }
    out[id] = {
      // A nested timeline spans its tweens, so only a tween is a window.
      tweens: tl
        .getChildren(true, true, false)
        .filter((c) => !c.getChildren)
        .map((c) => [lift(c, c.startTime()), lift(c, c.endTime())]),
      // A timeline a script registers beyond its scene's has no element.
      sounds: [
        ...(document
          .querySelector(`[data-composition-id="${id}"]`)
          ?.querySelectorAll("audio[data-start]") ?? []),
      ].map((a) => ({
        id: a.id,
        start: r3(+a.dataset.start),
        authored: a.id && authored.has(a.id) ? authored.get(a.id) : null,
      })),
    };
  }
  return out;
}

// The text the project shows at each of `times`, and what moves and sounds in
// each scene: `{ frames: [{ t, texts }], events: { <scene>: { tweens, sounds } } }`.
export async function probe(dir, times, { env }) {
  const { page, close } = await open(dir, env);
  try {
    const frames = [];
    for (const t of times) {
      await seek(page, t);
      frames.push({ t, texts: await page.evaluate(measureFrame) });
    }
    return { frames, events: await page.evaluate(sceneEvents) };
  } finally {
    await close();
  }
}
