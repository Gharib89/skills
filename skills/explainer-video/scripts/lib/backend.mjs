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

// One scene's stretch of the delivered video as a small MP4: a board card plays
// its own scene, and 960 wide keeps a 30 s scene well under the 15 MB asset cap.
export async function clip(input, output, { start, duration }) {
  ffmpeg([
    ...["-y", "-ss", String(start), "-t", String(duration), "-i", input],
    ...["-vf", "scale=960:-2", "-c:v", "libx264", "-preset", "veryfast"],
    ...["-crf", "30", "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart"],
    output,
  ]);
}

// A scene's contact sheet for the critic: four frames of the encoded video (its
// quarter marks and its settled last frame) at half size on a 2x2 grid. Cut by
// ffmpeg, never by HyperFrames' snapshot, which sends frames to Gemini.
export async function sheet(input, output, { start, duration, fps }) {
  const [first, picks] = sheetFrames({ start, duration, fps });
  ffmpeg([
    ...["-y", "-ss", String(start), "-t", String(duration), "-i", input],
    "-vf",
    `select='${picks.map((f) => `eq(n,${f - first})`).join("+")}',scale=960:540,tile=2x2`,
    ...["-frames:v", "1", output],
  ]);
}

// The scene's first frame and the four a sheet shows, as indices into the
// video. A scene owns the frames from the first at or after its start to the
// last before its end, so one starting between frames (28.25 s at 30 fps) never
// shows the next scene's first frame as its last.
export function sheetFrames({ start, duration, fps }) {
  const at = (t) => Math.ceil(t * fps - 1e-6);
  const first = at(start);
  const n = at(start + duration) - first;
  return [
    first,
    [n / 4, n / 2, (3 * n) / 4, n - 1].map((f) => first + Math.floor(f)),
  ];
}

// A scene's narration WAV as audio-only WebM (Opus): the artifact asset upload
// takes video types but no audio type, and a card's <audio> plays it as is.
export async function narration(input, output) {
  ffmpeg(["-y", "-i", input, "-vn", "-c:a", "libopus", "-b:a", "64k", output]);
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
// A `bed` (a stereo WAV, the score) is summed under the narration before the
// loudnorm, and the master then takes the bed's 48 kHz.
export async function master(input, output, { lufs, peak, bed }) {
  const loud = `loudnorm=I=${lufs}:TP=${peak}:LRA=11`;
  const target = bed
    ? `[0:a]pan=stereo|c0=c0|c1=c0[v];[v][1:a]amix=inputs=2:duration=first:normalize=0,${loud}`
    : `pan=stereo|c0=c0|c1=c0,${loud}`;
  const inputs = ["-i", input, ...(bed ? ["-i", bed] : [])];
  const filter = bed ? "-filter_complex" : "-af";
  const err = ffmpeg([
    ...inputs,
    filter,
    `${target}:print_format=json`,
    "-f",
    "null",
    "-",
  ]);
  const m = err.match(/\{[^{}]*"input_i"[^{}]*\}/)?.[0];
  if (!m)
    throw new Error(`loudnorm pass 1 printed no measurements for ${input}`);
  const j = JSON.parse(m);
  // With a score, its rate; without, the narration's own.
  const rate = bed ? 48000 : sampleRate(input);
  ffmpeg([
    "-y",
    ...inputs,
    filter,
    `${target}:measured_I=${j.input_i}:measured_TP=${j.input_tp}:measured_LRA=${j.input_lra}:measured_thresh=${j.input_thresh}:offset=${j.target_offset}:linear=true`,
    "-ar",
    String(rate),
    "-c:a",
    "pcm_s16le",
    output,
  ]);
}

function sampleRate(input) {
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
  return rate;
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
        ? { title: a.title || document.title, html: a.content }
        : { title: document.title, html: document.body?.innerHTML ?? "" };
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
    const fonts = new Set();
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
        const family = (el) =>
          el &&
          getComputedStyle(el)
            .fontFamily.split(",")[0]
            .replace(/["']/g, "")
            .trim();
        const links = [
          ...document.querySelectorAll("nav a[href], header a[href]"),
        ]
          .map((a) => new URL(a.href, location.href))
          .filter((l) => l.origin === location.origin)
          .map((l) => l.origin + l.pathname + l.search);
        return {
          colors,
          fonts: [document.body, document.querySelector("h1, h2")]
            .map(family)
            .filter(Boolean),
          links,
        };
      });
      const f = `${out}-${images.length + 1}.png`;
      await page.screenshot({ path: f });
      images.push(f);
      found.colors.forEach((c) => colors.add(c));
      found.fonts.forEach((c) => fonts.add(c));
      if (u === url) queue.push(...found.links);
    }
    return { images, colors: [...colors], fonts: [...fonts] };
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
