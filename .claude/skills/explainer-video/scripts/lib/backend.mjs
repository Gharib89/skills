// Everything setup and the stages reach outside the machine or the skill: npm,
// HyperFrames' Chrome download and render, ffprobe, the Fontsource API and CDN,
// Hugging Face, PATH, the models, and the source readers. Callers load it
// through tools.mjs's loadBackend.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import { createRequire } from "node:module";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { toolPaths } from "./tools.mjs";

const win = process.platform === "win32";
// Children write to stderr, so stdout carries only setup's own table.
const quiet = ["ignore", 2, 2];

// The lock's only install scripts are esbuild's and onnxruntime-node's, and
// neither is needed: esbuild's binary arrives as an optional dependency, the
// onnxruntime CPU binding ships in its tarball. Ignoring them keeps npm 10 and
// npm 11 alike, and stops npm 11's unapproved-script warning, which agents
// misread as a step left to do.
export async function npmCi(dir, env) {
  // npm is npm.cmd on Windows, which spawn runs only through a shell.
  return (
    spawnSync("npm", ["ci", "--no-audit", "--no-fund", "--ignore-scripts"], {
      cwd: dir,
      env,
      stdio: quiet,
      shell: win,
    }).status ?? 1
  );
}

// HyperFrames downloads its pinned Chrome to `homedir()/.cache/hyperframes/chrome`
// (0.8.160) with no setting to move it, so `home` stands in for the home folder:
// HOME for Node on Linux and macOS, USERPROFILE on Windows.
export async function ensureChrome(nodeDir, home, env) {
  const childEnv = { ...env, HOME: home, USERPROFILE: home };
  delete childEnv.HYPERFRAMES_BROWSER_PATH;
  const cli = path.join(
    nodeDir,
    "node_modules",
    "hyperframes",
    "bin",
    "hyperframes.mjs",
  );
  return (
    spawnSync(process.execPath, [cli, "browser", "ensure"], {
      env: childEnv,
      stdio: quiet,
    }).status ?? 1
  );
}

// The render stage's HyperFrames calls, through the CLI in the tool cache. The
// stage builds `env` (Chrome's home, the no-telemetry variables).
export async function hyperframes(args, { cwd, env }) {
  const cli = path.join(
    toolPaths().node,
    "node_modules",
    "hyperframes",
    "bin",
    "hyperframes.mjs",
  );
  return (
    spawnSync(process.execPath, [cli, ...args], { cwd, env, stdio: quiet })
      .status ?? 1
  );
}

// `hyperframes check` on the frames at `times`: its JSON report on exit 0 (clean)
// or 1 (findings). It writes `.hyperframes/` into the folder, removed after so
// the composition stays as written.
export async function check(dir, times, { env }) {
  const cli = path.join(
    toolPaths().node,
    "node_modules",
    "hyperframes",
    "bin",
    "hyperframes.mjs",
  );
  const r = spawnSync(
    process.execPath,
    [cli, "check", "--json", "--at", times.join(","), dir],
    {
      env,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 1 << 26,
    },
  );
  fs.rmSync(path.join(dir, ".hyperframes"), { recursive: true, force: true });
  process.stderr.write(r.stderr ?? "");
  const fail = () =>
    new Error(
      `hyperframes check exited ${r.status ?? r.signal}: ${(r.stderr || r.error?.message || "").split("\n")[0]}`,
    );
  if (r.status !== 0 && r.status !== 1) throw fail();
  try {
    return JSON.parse(r.stdout);
  } catch {
    throw fail();
  }
}

const MIME = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".wav": "audio/wav",
  ".woff2": "font/woff2",
  ".woff": "font/woff",
  ".ttf": "font/ttf",
  ".otf": "font/otf",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
};

// Runs in the page for one frame: the visible text owners and their geometry.
// Measurements only; the layout gate judges them.
function measureFrame() {
  const hex = (c) =>
    "#" +
    c
      .match(/[\d.]+/g)
      .slice(0, 3)
      .map((v) => Math.round(+v).toString(16).padStart(2, "0"))
      .join("");
  const r1 = (n) => Math.round(n * 10) / 10;
  const box = (r) => ({
    left: r1(r.left),
    top: r1(r.top),
    right: r1(r.right),
    bottom: r1(r.bottom),
  });
  const sub = '[data-composition-id]:not([data-composition-id="main"])';
  const out = [];
  for (const el of document.querySelectorAll("#root *")) {
    const own = [...el.childNodes]
      .filter((n) => n.nodeType === 3 && n.textContent.trim())
      .map((n) => n.textContent.trim())
      .join(" ");
    if (!own || !el.checkVisibility({ visibilityProperty: true })) continue;
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const scale = el.offsetHeight > 0 ? r.height / el.offsetHeight : 1;
    let opacity = 1;
    let clip = null;
    let bg = null;
    for (let a = el; a; a = a.parentElement) {
      const acs = getComputedStyle(a);
      opacity *= +acs.opacity;
      if (!clip && a !== el && acs.overflow !== "visible")
        clip = box(a.getBoundingClientRect());
      if (!bg && !/rgba\(.*, 0\)$|transparent/.test(acs.backgroundColor))
        bg = hex(acs.backgroundColor);
    }
    out.push({
      text: own.slice(0, 60),
      scene: el.closest(sub)?.dataset.compositionId ?? null,
      rect: box(r),
      fontPx: parseFloat(cs.fontSize) * scale,
      weight: +cs.fontWeight,
      inline: cs.display === "inline",
      scrollW: el.scrollWidth,
      scrollH: el.scrollHeight,
      clientW: el.clientWidth,
      clientH: el.clientHeight,
      opacity,
      clip,
      color: hex(cs.color),
      bg: bg ?? "#ffffff",
    });
  }
  return out;
}

export function findChrome(home) {
  const root = path.join(home, ".cache", "hyperframes", "chrome");
  const stack = [root];
  while (stack.length) {
    for (const e of fs.readdirSync(stack.pop(), { withFileTypes: true })) {
      const f = path.join(e.parentPath, e.name);
      if (e.isDirectory()) stack.push(f);
      else if (/^chrome(-headless-shell)?(\.exe)?$/.test(e.name)) return f;
    }
  }
  throw new Error(`no Chrome under ${root}`);
}

// The layout probe's measurements at `times`, unjudged. The composition is
// served as `hyperframes check` sees it: its folder over HTTP with the
// HyperFrames runtime injected into index.html, which mounts the
// data-composition-src scenes and sets window.__renderReady.
export async function probe(dir, times, { env }) {
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
  try {
    browser = await fromCache(nodeDir)("puppeteer-core").launch({
      headless: true,
      executablePath: findChrome(env.HOME),
      args: ["--no-sandbox", "--font-render-hinting=none"],
    });
    const page = await browser.newPage();
    await page.setViewport({ width: 1920, height: 1080 });
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
    const frames = [];
    for (const t of times) {
      await page.evaluate(async (t) => {
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
      frames.push({ t, elements: await page.evaluate(measureFrame) });
    }
    return frames;
  } finally {
    await browser?.close();
    server.close();
  }
}

function ffmpeg(args) {
  const r = spawnSync("ffmpeg", ["-hide_banner", "-nostats", ...args], {
    encoding: "utf8",
    maxBuffer: 1 << 26,
  });
  if (r.status !== 0)
    throw new Error(
      `ffmpeg exited ${r.status ?? r.error?.message}: ${(r.stderr || "").trim().split("\n").pop()}`,
    );
  return r.stderr;
}

// Integrated loudness (LUFS) and true peak (dBTP) of a file's audio, as
// ffmpeg's ebur128 summary prints them.
export async function loudness(file) {
  const err = ffmpeg([
    "-i",
    file,
    "-af",
    "ebur128=peak=true",
    "-f",
    "null",
    "-",
  ]);
  const summary = err.slice(err.lastIndexOf("Summary:"));
  const lufs = summary.match(/\n\s*I:\s*(-?[\d.]+|-inf) LUFS/)?.[1];
  const peak = summary.match(
    /True peak:[\s\S]*?Peak:\s*(-?[\d.]+|-inf) dBFS/,
  )?.[1];
  if (lufs === undefined || peak === undefined || lufs === "-inf")
    throw new Error(`ffmpeg ebur128 gave no loudness for ${file}`);
  return { lufs: +lufs, peak: +peak };
}

// Two-pass loudnorm to `lufs` integrated and `peak` true peak (LRA 11), as
// 16-bit stereo PCM WAV at the input's rate. Pass 2 is linear from pass 1's
// measurements, so speech keeps its dynamics. Mastered as stereo, both
// channels the source's: HyperFrames upmixes a mono track at full level into
// each channel (pan FL=FL+FC), which reads 3 LU louder than the mono master.
export async function master(input, output, { lufs, peak }) {
  const target = `pan=stereo|c0=c0|c1=c0,loudnorm=I=${lufs}:TP=${peak}:LRA=11`;
  const err = ffmpeg([
    "-i",
    input,
    "-af",
    `${target}:print_format=json`,
    "-f",
    "null",
    "-",
  ]);
  const m = err.match(/\{[^{}]*"input_i"[^{}]*\}/)?.[0];
  if (!m)
    throw new Error(`loudnorm pass 1 printed no measurements for ${input}`);
  const j = JSON.parse(m);
  const probed = spawnSync(
    "ffprobe",
    [
      "-v",
      "error",
      "-select_streams",
      "a:0",
      "-show_entries",
      "stream=sample_rate",
      "-of",
      "csv=p=0",
      input,
    ],
    { encoding: "utf8" },
  );
  const rate = parseInt(probed.stdout, 10);
  if (probed.status !== 0 || !rate)
    throw new Error(`ffprobe ${input}: no audio sample rate`);
  ffmpeg([
    "-y",
    "-i",
    input,
    "-af",
    `${target}:measured_I=${j.input_i}:measured_TP=${j.input_tp}:measured_LRA=${j.input_lra}:measured_thresh=${j.input_thresh}:offset=${j.target_offset}:linear=true`,
    "-ar",
    String(rate),
    "-c:a",
    "pcm_s16le",
    output,
  ]);
}

export async function ffprobe(file) {
  const r = spawnSync(
    "ffprobe",
    ["-v", "error", "-show_streams", "-show_format", "-of", "json", file],
    { encoding: "utf8" },
  );
  if (r.status !== 0)
    throw new Error(`ffprobe ${file}: ${r.stderr.trim() || r.error?.message}`);
  return JSON.parse(r.stdout);
}

export async function fontMeta(id) {
  const r = await fetch(
    `https://api.fontsource.org/v1/fonts/${encodeURIComponent(id)}`,
  );
  if (!r.ok)
    throw new Error(`Fontsource has no family ${id} (HTTP ${r.status})`);
  return r.json();
}

export async function download(url, file) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
}

export function which(cmd) {
  const exts = win
    ? (process.env.PATHEXT || ".EXE;.CMD;.BAT").split(";")
    : [""];
  for (const dir of (process.env.PATH || "").split(path.delimiter)) {
    for (const ext of exts) {
      const f = path.join(dir, cmd + ext);
      if (fs.statSync(f, { throwIfNoEntry: false })?.isFile()) return f;
    }
  }
  return null;
}

// The voice stage's models load from the tool cache, never the skill's folder:
// `tools.node` is the npm install, `tools.models` each model row's folder by id.
const fromCache = (nodeDir) =>
  createRequire(path.join(nodeDir, "package.json"));

// A narrator adapter: text in, audio out, never timings (ADR 0016). Kokoro
// reads one sentence per inference, so the whole text goes through its splitter.
let kokoro;
export async function synthesize({ text, narrator, tools }) {
  if (narrator.backend !== "kokoro")
    throw new Error(`no adapter for backend ${narrator.backend}`);
  const req = fromCache(tools.node);
  const { KokoroTTS, TextSplitterStream } = req("kokoro-js");
  if (!kokoro) {
    // kokoro-js's own dependency, pinned by the lock: requiring it from the same
    // install yields the instance kokoro-js reads its settings from.
    const { env } = req("@huggingface/transformers");
    env.allowRemoteModels = false;
    // An absolute path is read as a folder; a name under localModelPath must
    // pass the hub's model-id check, which the `@` in the cache name fails.
    kokoro = await KokoroTTS.from_pretrained(tools.models["model:kokoro-82m"], {
      dtype: "fp32",
      device: "cpu",
    });
  }
  // A plain string passed to stream() is never closed, so its last sentence
  // never yields (kokoro-js 1.2.1).
  const split = new TextSplitterStream();
  split.push(text);
  split.close();
  const parts = [];
  for await (const { audio } of kokoro.stream(split, { voice: narrator.voice }))
    parts.push(audio.audio);
  const samples = new Float32Array(parts.reduce((n, p) => n + p.length, 0));
  parts.reduce((o, p) => (samples.set(p, o), o + p.length), 0);
  return { samples, sampleRate: 24000 };
}

// One CTC model per language (ADR 0016).
const ALIGNERS = { en: "model:wav2vec2-base-960h" };

// A language's CTC model: its vocabulary, and its logits for 16 kHz audio,
// normalised as its feature extractor does.
export async function aligner({ language, tools }) {
  if (!ALIGNERS[language])
    throw new Error(`no aligner for language ${language}`);
  const dir = tools.models[ALIGNERS[language]];
  const ort = fromCache(tools.node)("onnxruntime-node");
  const session = await ort.InferenceSession.create(
    path.join(dir, "onnx", "model_int8.onnx"),
  );
  const vocab = JSON.parse(
    fs.readFileSync(path.join(dir, "vocab.json"), "utf8"),
  );
  async function logits(x) {
    let mean = 0;
    for (const v of x) mean += v;
    mean /= x.length;
    let sq = 0;
    for (const v of x) sq += (v - mean) ** 2;
    const sd = Math.sqrt(sq / x.length + 1e-7);
    const input = new ort.Tensor(
      "float32",
      x.map((v) => (v - mean) / sd),
      [1, x.length],
    );
    const out = (await session.run({ [session.inputNames[0]]: input }))[
      session.outputNames[0]
    ];
    return { data: out.data, frames: out.dims[1], classes: out.dims[2] };
  }
  return { vocab, logits };
}

// The source stage's readers, each one format to text or HTML; the stage turns
// HTML to Markdown through toMarkdown and splits each snapshot by locator.

// A web page (or a local HTML file, by its file: URL) as it reads once its
// scripts have run: loaded in HyperFrames' Chrome until the network is idle,
// then Readability, run inside the page, keeps the article. A page Readability
// finds no article in keeps its whole body.
export async function renderPage(url, { env }) {
  const req = fromCache(toolPaths().node);
  const browser = await req("puppeteer-core").launch({
    headless: true,
    executablePath: findChrome(env.HOME),
    args: ["--no-sandbox"],
  });
  try {
    const page = await browser.newPage();
    // A page that never goes idle (a poll, a stream) is read as it stands.
    await page
      .goto(url, { waitUntil: "networkidle0", timeout: 30000 })
      .catch((e) => {
        if (e.name !== "TimeoutError") throw e;
      });
    await page.addScriptTag({
      path: req.resolve("@mozilla/readability/Readability.js"),
    });
    return await page.evaluate(() => {
      const a = new window.Readability(document.cloneNode(true)).parse();
      return a?.content
        ? { title: a.title || document.title, html: a.content }
        : { title: document.title, html: document.body?.innerHTML ?? "" };
    });
  } finally {
    await browser.close();
  }
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
