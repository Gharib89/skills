// The backend's toolchain: npm, HyperFrames' Chrome and its layout probe.
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { skill, toolPaths, torchDevice } from "../tools.mjs";
import { fromCache, quiet, which, win } from "./common.mjs";

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
  // A colour as `#rrggbb`, its alpha dropped. A `color-mix` serializes as
  // `color(srgb r g b / a)` with channels from 0 to 1.
  const hex = (c) =>
    "#" +
    c
      .match(/[\d.]+/g)
      .slice(0, 3)
      .map((v) =>
        Math.round(c.startsWith("color(") ? +v * 255 : +v)
          .toString(16)
          .padStart(2, "0"),
      )
      .join("");
  // A colour as [r, g, b, alpha], channels 0 to 255, in any form the computed
  // style takes (`rgb`, `rgba`, `color(srgb ...)`).
  const rgba = (c) => {
    const n = c.match(/[\d.]+/g).map(Number);
    const k = c.startsWith("color(") ? 255 : 1;
    return [n[0] * k, n[1] * k, n[2] * k, n.length > 3 ? n[3] : 1];
  };
  const r1 = (n) => Math.round(n * 10) / 10;
  const box = (r) => ({
    left: r1(r.left),
    top: r1(r.top),
    right: r1(r.right),
    bottom: r1(r.bottom),
  });
  // The part of `a` that `b` also covers: the box a clip by both leaves.
  const meet = (a, b) => ({
    left: Math.max(a.left, b.left),
    top: Math.max(a.top, b.top),
    right: Math.min(a.right, b.right),
    bottom: Math.min(a.bottom, b.bottom),
  });
  // Whether a `clip-path` cuts into an element's boxes, as the browser's hit
  // test says: a clipped-away point reaches neither the element nor anything in
  // it, whatever shape the path is. Each line box of an inline element is
  // tried, at its corners and centre, and only where the viewport and the
  // `overflow` clips (`clip`) leave the page visible: a hit test misses outside
  // the viewport, and it respects an `overflow` clip too, which `clipped`
  // already reports. A hit test skips an element with `pointer-events: none`,
  // which the video never shows, so the element answers to `auto`, important so
  // that no rule's `!important` outranks it, for the test and is put back
  // after, priority and all.
  const cutByPath = (el, clip) => {
    const view = { left: 0, top: 0, right: innerWidth, bottom: innerHeight };
    const seen = clip ? meet(view, clip) : view;
    const was = el.style.getPropertyValue("pointer-events");
    const priority = el.style.getPropertyPriority("pointer-events");
    el.style.setProperty("pointer-events", "auto", "important");
    try {
      return [...el.getClientRects()].some((r) =>
        [0, 0.5, 1].some((fx) =>
          [0, 0.5, 1].some((fy) => {
            const x = r.left + 1 + (r.width - 2) * fx;
            const y = r.top + 1 + (r.height - 2) * fy;
            return (
              r.width > 2 &&
              r.height > 2 &&
              x >= seen.left &&
              y >= seen.top &&
              x < seen.right &&
              y < seen.bottom &&
              !document.elementsFromPoint(x, y).some((hit) => el.contains(hit))
            );
          }),
        ),
      );
    } finally {
      el.style.setProperty("pointer-events", was, priority);
    }
  };
  const sub = '[data-composition-id]:not([data-composition-id="main"])';
  // The ink Arabic's letters span in an element's face and weight, in ems, as
  // canvas measures it once per face and weight: the least line height that
  // keeps two lines of them apart. Every letter and hamza seat, no marks: the
  // floor is the face's, not the line's, and a stress line of stacked marks
  // (1.6 em in IBM Plex Sans Arabic) would fail the profiles' own 1.5 and 1.6
  // heights.
  const pen = document.createElement("canvas").getContext("2d");
  const LETTERS = "ءآأإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىي";
  const inks = new Map();
  const ink = (cs) => {
    const key = `${cs.fontWeight} ${cs.fontFamily}`;
    if (!inks.has(key)) {
      pen.font = `${cs.fontWeight} 100px ${cs.fontFamily}`;
      const m = pen.measureText(LETTERS);
      inks.set(
        key,
        Math.round(m.actualBoundingBoxAscent + m.actualBoundingBoxDescent) /
          100,
      );
    }
    return inks.get(key);
  };
  const out = [];
  for (const [nth, el] of [...document.querySelectorAll("#root *")].entries()) {
    const own = [...el.childNodes]
      .filter((n) => n.nodeType === 3 && n.textContent.trim())
      .map((n) => n.textContent.trim())
      .join(" ");
    if (!own || !el.checkVisibility({ visibilityProperty: true })) continue;
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const scale = el.offsetHeight > 0 ? r.height / el.offsetHeight : 1;
    let opacity = 1;
    let blur = 0;
    let clip = null;
    let clipPath = false;
    let bg;
    let solid = false;
    const layers = [];
    for (let a = el; a; a = a.parentElement) {
      const acs = getComputedStyle(a);
      opacity *= +acs.opacity;
      blur = Math.max(
        blur,
        parseFloat(/blur\(([\d.]+)px\)/.exec(acs.filter)?.[1] ?? 0),
      );
      // Every clipping ancestor cuts, so the box is where they all overlap.
      if (a !== el && acs.overflow !== "visible") {
        const b = box(a.getBoundingClientRect());
        clip = clip ? meet(clip, b) : b;
      }
      if (acs.clipPath !== "none") clipPath = true;
      if (!solid) {
        const [r, g, b, al] = rgba(acs.backgroundColor);
        if (al > 0) layers.push([r, g, b, al]);
        solid = al === 1;
      }
    }
    // A box that takes no pointer cannot be hit tested.
    const cut = clipPath && cutByPath(el, clip);
    // A code excerpt's line keeps its indent as plain text before the code's
    // span: how many characters it has, and how far the code sits from the
    // line's start in the frame.
    const line = el.closest(".xcode .xs");
    const lead =
      line?.firstChild?.nodeType === 3
        ? /^\s*/.exec(line.firstChild.textContent)[0].length
        : 0;
    // The box's ground: each see-through layer (the glass surface) over the
    // ones behind it, down to the first opaque one, else white.
    const ground = layers.reduceRight(
      (under, [r, g, b, al]) =>
        [r, g, b].map((v, i) => v * al + under[i] * (1 - al)),
      [255, 255, 255],
    );
    bg =
      "#" +
      ground.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("");
    out.push({
      text: own.slice(0, 60),
      words: own.trim().split(/\s+/).length,
      scene: el.closest(sub)?.dataset.compositionId ?? null,
      // A kinetic line is one box: its words share a `data-line`, and
      // `data-along` marks one revealed on its own spoken words.
      line: el.closest("[data-line]")?.dataset.line ?? null,
      // The element's place in the page, the same on every sample, so two
      // boxes with the same text stay two.
      nth,
      along: el.closest("[data-along]") !== null,
      rect: box(r),
      fontPx: parseFloat(cs.fontSize) * scale,
      weight: +cs.fontWeight,
      inline: cs.display === "inline",
      rows: [...el.getClientRects()].map((q) => [r1(q.top), r1(q.bottom)]),
      scrollW: el.scrollWidth,
      scrollH: el.scrollHeight,
      clientW: el.clientWidth,
      clientH: el.clientHeight,
      opacity,
      blur,
      clip,
      cut,
      indent: lead
        ? { want: lead, got: r1(r.left - line.getBoundingClientRect().left) }
        : null,
      color: hex(cs.color),
      bg,
      // Reading direction: the element's own, the `dir` it sits in, how it
      // is isolated and wrapped, and its line height against its ink.
      dir: cs.direction,
      within: el.parentElement?.closest("[dir]")?.getAttribute("dir") ?? null,
      bidi: cs.unicodeBidi,
      wrap: cs.whiteSpace,
      lineH:
        cs.lineHeight === "normal"
          ? null
          : Math.round(
              (parseFloat(cs.lineHeight) / parseFloat(cs.fontSize)) * 100,
            ) / 100,
      face: cs.fontFamily.split(",")[0].replace(/["']/g, "").trim(),
      ink: ink(cs),
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

// The composition open in a fresh browser, ready to seek. It is served as
// `hyperframes check` sees it: its folder over HTTP with the HyperFrames
// runtime injected into index.html, which mounts the data-composition-src
// scenes and sets window.__renderReady. With `software`, Chrome draws WebGL on
// SwiftShader, the CPU renderer, so two launches agree to the pixel where a host
// GPU's frames may not.
async function openComposition(dir, env, software = false) {
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
      args: [
        "--no-sandbox",
        "--font-render-hinting=none",
        ...(software
          ? [
              "--use-gl=angle",
              "--use-angle=swiftshader",
              "--enable-unsafe-swiftshader",
            ]
          : []),
      ],
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
// The layout probe's measurements at `times`, unjudged.
export async function probe(dir, times, { env }) {
  const { page, close } = await openComposition(dir, env);
  try {
    const frames = [];
    for (const t of times) {
      await seek(page, t);
      frames.push({
        t,
        elements: await page.evaluate(measureFrame),
        // The page roots carrying a `dir`, which belongs on text boxes alone.
        rootDir: await page.evaluate(() =>
          [
            document.documentElement,
            document.body,
            document.getElementById("root"),
          ]
            .filter((e) => e?.hasAttribute("dir"))
            .map((e) => (e.id ? `#${e.id}` : e.localName)),
        ),
      });
    }
    return frames;
  } finally {
    await close();
  }
}

// Each scene's timeline events, in the scene's own seconds: the end of every
// child on its GSAP timeline, the `[start, end]` of every tween on it, and the `seam:start`/`seam:end` and
// `camera:start`/`camera:end` label pairs that mark when its seam or camera
// runs; both label pairs come from the scene's script (render/seam-script.mjs).
export async function events(dir, { env }) {
  const { page, close } = await openComposition(dir, env);
  try {
    return await page.evaluate(() => {
      const r3 = (n) => Math.round(n * 1000) / 1000;
      const out = {};
      for (const [id, tl] of Object.entries(window.__timelines ?? {})) {
        if (id === "main") continue;
        // Every `<kind>:start<n>`/`<kind>:end<n>` pair, `<n>` blank or a
        // number: a scene has a seam in and a seam out.
        const pair = (kind) =>
          Object.keys(tl.labels)
            .map((k) => k.match(new RegExp(`^${kind}:start(\\d*)$`)))
            .filter((m) => m && `${kind}:end${m[1]}` in tl.labels)
            .map((m) => [
              r3(tl.labels[m[0]]),
              r3(tl.labels[`${kind}:end${m[1]}`]),
            ]);
        const seams = pair("seam");
        const camera = pair("camera");
        // startTime() and endTime() are in the parent's time: lift a nested
        // tween's through each ancestor's start to the scene timeline's.
        const lift = (c, t) => {
          for (let p = c.parent; p && p !== tl; p = p.parent)
            t = p.startTime() + t / p.timeScale();
          return r3(t);
        };
        const kids = tl.getChildren(true, true, false);
        const ends = kids.map((c) => lift(c, c.endTime()));
        // A nested timeline spans its tweens, so only a tween is a window.
        const tweens = kids
          .filter((c) => !c.getChildren)
          .map((c) => [lift(c, c.startTime()), lift(c, c.endTime())]);
        out[id] = { ends, tweens, seams, camera };
      }
      return out;
    });
  } finally {
    await close();
  }
}

// The composition's frame at `t` as a PNG, in a browser launched for it alone:
// the probe's seek then a screenshot, the route that needs no second renderer.
// `software` renders WebGL on SwiftShader, as the determinism gate needs of a
// scene that draws it.
export async function frame(dir, t, out, { env, software = false }) {
  const { page, close } = await openComposition(dir, env, software);
  try {
    await seek(page, t);
    await page.screenshot({ path: out, type: "png" });
  } finally {
    await close();
  }
}
