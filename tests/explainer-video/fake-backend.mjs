// The canned backend tests select with EXPLAINER_VIDEO_BACKEND: the real one's
// exports, answering from fixtures and logging each call as one JSON line to
// $EXPLAINER_VIDEO_FAKE_LOG, so a test asserts on what a stage asked for.
//   EXPLAINER_VIDEO_FAKE_PRESENT  comma-separated commands `which` finds
//   EXPLAINER_VIDEO_FAKE_PROBE    JSON fields overriding what ffprobe and
//                                 loudness answer
//   EXPLAINER_VIDEO_FAKE_CHECK    JSON check answers in place of its own
//   EXPLAINER_VIDEO_FAKE_CLIP_BYTES  size of each clip written (default 1000)
//   EXPLAINER_VIDEO_FAKE_ACE_EXIT  ACE-Step's exit code, thrown as the real
//                                  one throws it (unset, it makes the music)
// The family `ubuntu` answers with its real, non-OFL licence; `helvetica-neue`
// and `georgia`, as on the real Fontsource, with no family at all.
//
// Fake audio is 16 kHz and spells its text: each letter holds 3 frames of 320
// samples (2 at the letter's vocabulary id / 100, 1 silent), each word ends on
// a `|` frame and 2 silent frames, each sentence on 10 more. The fake aligner
// reads a frame's id back from its first sample, so word timings come out of
// the real Viterbi pass. A sentence naming a marker word misrenders:
// `garbled` speaks every word as "mumble", `looped` speaks the sentence twice,
// `slowly` holds each letter 8 frames. A `gemini` narrator speaks Arabic the
// same way in the Egyptian aligner's vocabulary (see gemini below), and
//   EXPLAINER_VIDEO_FAKE_QUOTA  a Gemini call throws the real quota error once
//                               this many synthesize calls are in the log
// geminiKey refuses the key `bad-key` as API_KEY_INVALID and takes any other.
//
// The gates' measures read the composition: probe reports each text element of
// the scenes mounted at a time, and the caption cue showing then, at 40 px in
// the content band with the palette's text on its bg, all in bounds. An
// element whose text names a marker word misrenders: `clipped` overflows
// (scrollW 4000 in 1600) past its clip box, and check reports it as a layout
// error `text_box_overflow`; `tiny` is 12 px; `dim` is #c8c8c0; `small` is 20 px
// in the palette's accent; `edge` sits at
// left 40, inside the safe margin; `stacked` starts halfway down the element
// before it, so the two overlap. EXPLAINER_VIDEO_FAKE_BLANK=1 makes probe find
// no text at all.
import fs from "node:fs";
import path from "node:path";

const log = (call) =>
  fs.appendFileSync(
    process.env.EXPLAINER_VIDEO_FAKE_LOG,
    JSON.stringify(call) + "\n",
  );

export async function npmCi(dir, env) {
  log({
    call: "npmCi",
    dir,
    onnxruntime: env.ONNXRUNTIME_NODE_INSTALL ?? null,
  });
  fs.mkdirSync(path.join(dir, "node_modules"), { recursive: true });
  fs.writeFileSync(path.join(dir, "node_modules", ".package-lock.json"), "{}");
  return 0;
}

export async function ensureChrome(nodeDir, home) {
  log({ call: "ensureChrome", nodeDir, home });
  fs.mkdirSync(path.join(home, ".cache", "hyperframes", "chrome"), {
    recursive: true,
  });
  fs.writeFileSync(
    path.join(home, ".cache", "hyperframes", "chrome", "chrome-headless-shell"),
    "x".repeat(1000),
  );
  return 0;
}

// Fontsource holds every family but `helvetica-neue` and `georgia`; a
// family's category is its entry in CATEGORY, else sans-serif.
const CATEGORY = {
  "source-serif-4": "serif",
  "noto-serif": "serif",
  "jetbrains-mono": "monospace",
};
export async function fontMeta(id) {
  log({ call: "fontMeta", id });
  if (["helvetica-neue", "georgia"].includes(id)) return null;
  return {
    id,
    category: CATEGORY[id] ?? "sans-serif",
    license: id === "ubuntu" ? "UFL-1.0" : "OFL-1.1",
    npmVersion: "5.3.0",
    weights: [400, 600],
    subsets: ["latin"],
    styles: ["normal"],
  };
}

export async function download(url, file) {
  log({ call: "download", url });
  fs.writeFileSync(file, "woff2");
}

// A source archive extracts to a pyproject; uv sync leaves a .venv beside it.
export async function extract(zip, dir) {
  log({ call: "extract", zip, dir });
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "pyproject.toml"), "[project]\n");
}

export async function uvSync(dir) {
  log({ call: "uvSync", dir });
  fs.mkdirSync(path.join(dir, ".venv"), { recursive: true });
  return 0;
}

// ACE-Step's music: a tone the seed tunes, 48 kHz stereo, `seconds` long.
export async function aceStep({ dir, device, seconds, seed, caption }) {
  log({ call: "aceStep", dir, device, seconds, seed, caption });
  const exit = process.env.EXPLAINER_VIDEO_FAKE_ACE_EXIT;
  if (exit) throw new Error(`ace-step exited ${exit}`);
  const n = Math.round(seconds * 48000);
  const hz = 110 + (seed % 200);
  const L = Float32Array.from({ length: n }, (_, i) =>
    Math.sin((2 * Math.PI * hz * i) / 48000),
  );
  return { L, R: Float32Array.from(L) };
}

// The machine: EXPLAINER_VIDEO_FAKE_GPU a compute capability (unset, no NVIDIA
// card), EXPLAINER_VIDEO_FAKE_RAM its bytes of RAM (default 64 GB).
export async function computeCapability() {
  const cap = process.env.EXPLAINER_VIDEO_FAKE_GPU;
  return cap ? +cap : null;
}

export function memory() {
  return +(process.env.EXPLAINER_VIDEO_FAKE_RAM ?? 64e9);
}

export function which(cmd) {
  return (process.env.EXPLAINER_VIDEO_FAKE_PRESENT ?? "")
    .split(",")
    .includes(cmd)
    ? `/usr/bin/${cmd}`
    : null;
}

const HOP = 320;
const VOCAB = Object.fromEntries(
  ["<pad>", "<s>", "</s>", "<unk>", "|", ..."ETAONIHSRDLUMWCFGYPBVK'XJQZ"].map(
    (c, i) => [c, i],
  ),
);
// The Egyptian Arabic aligner's vocabulary as its vocab.json holds it: `|` is
// 0, `[PAD]` (40) the blank, and the model's logits carry two classes more.
const AR_VOCAB = Object.fromEntries([
  ["|", 0],
  ..."ءآأإئابةتثجحخدذرزسشصضطظعغفقكلمنهوىيڨیﻻ"
    .split("")
    .map((c, i) => [c, i + 1]),
  ["[UNK]", 39],
  ["[PAD]", 40],
]);
const AR_CLASSES = 43;

// English terms as an Egyptian speaker says them, not as any rule spells them.
const SAID = {
  pull: "بول",
  request: "ريكويست",
  branch: "برانش",
  git: "جيت",
  ci: "سي اي",
  review: "ريفيو",
  merge: "ميرج",
  profile: "بروفايل",
  issue: "ايشو",
  agent: "ايجنت",
  ship: "شيب",
  github: "جيثوب",
  actions: "اكتيونس",
};

const synthCalls = () =>
  fs.existsSync(process.env.EXPLAINER_VIDEO_FAKE_LOG)
    ? fs
        .readFileSync(process.env.EXPLAINER_VIDEO_FAKE_LOG, "utf8")
        .split("\n")
        .filter((l) => l.includes('"call":"synthesize"')).length
    : 0;

const toSamples = (frames) => {
  const samples = new Float32Array(frames.length * HOP);
  frames.forEach((id, f) => samples.fill(id / 100, f * HOP, (f + 1) * HOP));
  return { samples, sampleRate: 16000 };
};

// A Gemini narrator speaks Arabic in the Arabic vocabulary's ids, blanks as
// `[PAD]`; its markers are مشوش (every word ممم), مكرر (the sentence twice) and
// ببطء (each letter held 8 frames).
function gemini(text, narrator) {
  const quota = process.env.EXPLAINER_VIDEO_FAKE_QUOTA;
  if (quota && synthCalls() >= +quota)
    throw Object.assign(
      new Error("Gemini answered HTTP 429: You exceeded your current quota"),
      { quota: true },
    );
  log({ call: "synthesize", backend: "gemini", voice: narrator.voice, text });
  const pad = AR_VOCAB["[PAD]"];
  const clean = text.normalize("NFKC").replace(/[ً-ْٰـ]/g, "");
  const frames = new Array(10).fill(pad);
  for (const sentence of clean.split(/(?<=[.!?؟])\s+/)) {
    let words = (sentence.match(/[ء-ي]+|[A-Za-z]+/g) ?? []).flatMap((w) => {
      if (!/[A-Za-z]/.test(w)) return [w];
      if (!SAID[w.toLowerCase()])
        throw new Error(`the fake cannot say ${w}: add it to SAID`);
      return SAID[w.toLowerCase()].split(" ");
    });
    const hold = sentence.includes("ببطء") ? 8 : 2;
    if (sentence.includes("مشوش")) words = words.map(() => "ممم");
    if (sentence.includes("مكرر")) words = [...words, ...words];
    for (const w of words) {
      for (const ch of w)
        frames.push(...new Array(hold).fill(AR_VOCAB[ch]), pad);
      frames.push(AR_VOCAB["|"], pad, pad);
    }
    frames.push(...new Array(10).fill(pad));
  }
  return toSamples(frames);
}

// A key check that spends no TTS request; the key itself is never logged.
export async function geminiKey(key) {
  log({ call: "geminiKey" });
  return key === "bad-key"
    ? { ok: false, reason: "API_KEY_INVALID" }
    : { ok: true };
}

export async function synthesize({ text, narrator, tools }) {
  if (narrator.backend === "gemini") return gemini(text, narrator);
  log({
    call: "synthesize",
    text,
    voice: narrator.voice,
    model: tools.models["model:kokoro-82m"],
  });
  const frames = new Array(10).fill(0);
  for (const sentence of text.split(/(?<=[.!?])\s+/)) {
    let words = sentence.toUpperCase().match(/[A-Z']+/g) ?? [];
    const hold = /\bslowly\b/i.test(sentence) ? 8 : 2;
    if (/\bgarbled\b/i.test(sentence)) words = words.map(() => "MUMBLE");
    if (/\blooped\b/i.test(sentence)) words = [...words, ...words];
    for (const w of words) {
      for (const ch of w) frames.push(...new Array(hold).fill(VOCAB[ch]), 0);
      frames.push(VOCAB["|"], 0, 0);
    }
    frames.push(...new Array(10).fill(0));
  }
  return toSamples(frames);
}

export async function aligner({ language }) {
  const vocab = language === "ar" ? AR_VOCAB : VOCAB;
  const classes = language === "ar" ? AR_CLASSES : Object.keys(VOCAB).length;
  return {
    vocab,
    async logits(x) {
      const frames = Math.floor(x.length / HOP);
      const data = new Float32Array(frames * classes);
      for (let f = 0; f < frames; f++)
        data[f * classes + Math.round(x[f * HOP] * 100)] = 10;
      return { data, frames, classes };
    },
  };
}

// A render writes what the fake ffprobe answers from: the composition's root
// duration at 1920x1080, 30 fps, with audio. A png-sequence writes one file
// per mounted scene. The log keeps the variables a stage set for the CLI.
export async function hyperframes(args, { cwd, env }) {
  const html = fs.readFileSync(path.join(cwd, "index.html"), "utf8");
  const hosts = [
    ...html.matchAll(/data-composition-src="scenes\/([^"]+)\.html"/g),
  ].map((m) => m[1]);
  log({
    call: "hyperframes",
    args,
    cwd,
    hosts,
    env: Object.fromEntries(
      [
        "HYPERFRAMES_NO_TELEMETRY",
        "DO_NOT_TRACK",
        "HYPERFRAMES_NO_UPDATE_CHECK",
        "HOME",
        "USERPROFILE",
      ].map((k) => [k, env[k] ?? null]),
    ),
  });
  const out = args[args.indexOf("-o") + 1];
  if (args.includes("png-sequence")) {
    fs.mkdirSync(out, { recursive: true });
    hosts.forEach((id, i) =>
      fs.writeFileSync(
        path.join(out, `frame_${String(i + 1).padStart(6, "0")}.png`),
        `still of ${id}`,
      ),
    );
  } else {
    const duration = +html.match(
      /data-composition-id="main"[^>]*data-duration="([\d.]+)"/,
    )[1];
    fs.writeFileSync(
      out,
      JSON.stringify({
        width: 1920,
        height: 1080,
        fps: 30,
        duration,
        audio: true,
        lufs: -14.0,
        peak: -1.6,
      }),
    );
  }
  return 0;
}

// Answers from the fake render's file, each field overridable through
// EXPLAINER_VIDEO_FAKE_PROBE (JSON), as ffprobe's -show_streams -show_format.
export async function ffprobe(file) {
  const v = {
    ...JSON.parse(fs.readFileSync(file, "utf8")),
    ...JSON.parse(process.env.EXPLAINER_VIDEO_FAKE_PROBE ?? "{}"),
  };
  log({ call: "ffprobe", file });
  return {
    streams: [
      {
        codec_type: "video",
        width: v.width,
        height: v.height,
        r_frame_rate: `${v.fps}/1`,
      },
      ...(v.audio ? [{ codec_type: "audio" }] : []),
    ],
    format: { duration: String(v.duration) },
  };
}

// Integrated loudness and true peak, from the fake render's file as ffprobe.
export async function loudness(file) {
  const v = {
    ...JSON.parse(fs.readFileSync(file, "utf8")),
    ...JSON.parse(process.env.EXPLAINER_VIDEO_FAKE_PROBE ?? "{}"),
  };
  log({ call: "loudness", file });
  return { lufs: v.lufs ?? -14.0, peak: v.peak ?? -1.6 };
}

export async function master(input, output, { lufs, peak, bed }) {
  log({ call: "master", input, output, lufs, peak, bed });
  fs.copyFileSync(input, output);
}

export async function clip(input, output, { start, duration }) {
  log({ call: "clip", input, output, start, duration });
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, "");
  fs.truncateSync(
    output,
    Number(process.env.EXPLAINER_VIDEO_FAKE_CLIP_BYTES ?? 1000),
  );
}

export async function sheet(input, output, { start, duration, fps }) {
  log({ call: "sheet", input, output, start, duration, fps });
  fs.writeFileSync(output, `sheet of ${path.basename(output, ".png")}`);
}

export async function narration(input, output) {
  log({ call: "narration", input, output });
  fs.mkdirSync(path.dirname(output), { recursive: true });
  if (process.env.EXPLAINER_VIDEO_FAKE_NARRATION_FAIL) {
    // ffmpeg -y opens its output before it encodes, so a failure leaves a part.
    fs.writeFileSync(output, "part");
    throw new Error("ffmpeg: encode failed");
  }
  fs.copyFileSync(input, output);
}

// What shows at t: each mounted scene's own text elements, and the caption
// cue's words joined.
function showing(dir, t) {
  const html = fs.readFileSync(path.join(dir, "index.html"), "utf8");
  const on = (start, duration) => t >= +start && t < +start + +duration;
  const texts = [];
  for (const m of html.matchAll(
    /data-composition-id="([^"]+)" data-composition-src="[^"]+" data-start="([\d.]+)" data-duration="([\d.]+)"/g,
  ))
    if (on(m[2], m[3])) {
      const scene = fs.readFileSync(
        path.join(dir, "scenes", `${m[1]}.html`),
        "utf8",
      );
      const rtl = /dir="rtl"/.test(scene);
      for (const e of scene.matchAll(/<(div|span|bdi)[^>]*>([^<]+)</g))
        if (e[2].trim())
          texts.push({
            scene: m[1],
            text: e[2].trim(),
            bdi: e[1] === "bdi",
            rtl,
          });
    }
  for (const m of html.matchAll(
    /<div class="cue clip" data-start="([\d.]+)" data-duration="([\d.]+)"[^>]*>(.*?)<\/div>/g,
  ))
    if (on(m[1], m[2])) {
      // A Latin run's <bdi> is an element of its own, as the browser sees it.
      const text = m[3]
        .replace(/<bdi[^>]*>[^<]*<\/bdi>/g, "")
        .replace(/<[^>]+>/g, "")
        .replace(/\s+/g, " ")
        .trim();
      const rtl = /^[^>]* dir="rtl"/.test(m[0]);
      if (text) texts.push({ scene: null, text, rtl });
      for (const r of m[3].matchAll(/<bdi[^>]*>([^<]+)<\/bdi>/g))
        texts.push({ scene: null, text: r[1], bdi: true, rtl });
    }
  return { html, texts };
}

export async function check(dir, times) {
  log({ call: "check", times });
  if (process.env.EXPLAINER_VIDEO_FAKE_CHECK)
    return JSON.parse(process.env.EXPLAINER_VIDEO_FAKE_CHECK);
  const findings = times.flatMap((t) =>
    showing(dir, t)
      .texts.filter((e) => /\bclipped\b/.test(e.text))
      .map((e) => ({
        code: "text_box_overflow",
        severity: "error",
        time: t,
        message: "text overflows its box",
        text: e.text,
        sourceFile: `scenes/${e.scene}.html`,
      })),
  );
  return {
    ok: !findings.length,
    layout: { findings },
    contrast: { findings: [] },
  };
}

// An element's reading direction as the composition sets it: Arabic text reads
// right to left in a scene or cue marked so; a Latin run's <bdi>
// sits in one, isolated, on one line where the `.lat` rule says so. A caption
// word's line height is the `.cue` rule's, against the ink #686 measured for
// IBM Plex Sans Arabic (1.46 em) and Inter (0.98 em).
function reading(html, scene, text, bdi, rtl) {
  const cue = html.match(/\.cue \{[^}]*font: \d+ [\d.]+px\/([\d.]+) "([^"]+)"/);
  const arabic = /\p{Script=Arabic}/u.test(text);
  return {
    dir: arabic && rtl ? "rtl" : "ltr",
    within: bdi && rtl ? "rtl" : null,
    bidi: bdi ? "isolate" : "normal",
    wrap:
      bdi && /\.lat \{[^}]*white-space: nowrap/.test(html)
        ? "nowrap"
        : "normal",
    lineH: scene === null && cue ? +cue[1] : null,
    face: cue?.[2] ?? null,
    ink: arabic ? 1.46 : 0.98,
  };
}

export async function probe(dir, times) {
  log({ call: "probe", times });
  return times.map((t) => {
    const { html, texts } = showing(dir, t);
    const color = (k) => html.match(new RegExp(`--${k}: (#[0-9a-f]{6});`))[1];
    if (process.env.EXPLAINER_VIDEO_FAKE_BLANK) return { t, elements: [] };
    return {
      t,
      elements: texts.map(({ scene, text, bdi, rtl }, i) => {
        const row = /\bstacked\b/.test(text) ? i - 0.5 : i;
        const top = scene ? 200 + row * 50 : 920;
        const left = /\bedge\b/.test(text) ? 40 : 160;
        const rect = { left, top, right: 1760, bottom: top + 48 };
        const clipped = /\bclipped\b/.test(text);
        return {
          text,
          scene,
          rect,
          fontPx: /\btiny\b/.test(text) ? 12 : /\bsmall\b/.test(text) ? 20 : 40,
          weight: 400,
          inline: false,
          scrollW: clipped ? 4000 : 1600,
          scrollH: 48,
          clientW: 1600,
          clientH: 48,
          opacity: 1,
          clip: clipped ? { ...rect, right: 1000 } : null,
          color: /\bdim\b/.test(text)
            ? "#c8c8c0"
            : /\bsmall\b/.test(text)
              ? color("accent")
              : color("text"),
          bg: color("bg"),
          ...reading(html, scene, text, bdi, rtl),
        };
      }),
      rootDir: [
        ["html", /<html[^>]*\sdir=/],
        ["body", /<body[^>]*\sdir=/],
        ["#root", /<div id="root"[^>]*\sdir=/],
      ]
        .filter(([, re]) => re.test(html))
        .map(([r]) => r),
    };
  });
}

// The source readers. A fixture .pdf holds `{"pages": [...]}` and a .pptx
// `{"parts": {path: xml}}`, both JSON; a .docx holds the HTML mammoth would
// give. renderPage answers a URL from the JSON map in
// $EXPLAINER_VIDEO_FAKE_PAGES ({url: {title, html}}), a file: URL from the
// file, as the page Chrome would hand Readability once its scripts ran.
export async function renderPage(url) {
  log({ call: "renderPage", url });
  if (url.startsWith("file:")) {
    const html = fs.readFileSync(new URL(url), "utf8");
    return {
      title: html.match(/<title>([^<]*)<\/title>/)?.[1] ?? "",
      html: html.replace(/^[\s\S]*<body>|<\/body>[\s\S]*$/g, ""),
    };
  }
  const page = JSON.parse(process.env.EXPLAINER_VIDEO_FAKE_PAGES ?? "{}")[url];
  if (!page) throw new Error(`net::ERR_NAME_NOT_RESOLVED at ${url}`);
  return page;
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
