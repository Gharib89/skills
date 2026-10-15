// The canned backend tests select with EXPLAINER_VIDEO_BACKEND: the real one's
// exports, answering from fixtures and logging each call as one JSON line to
// $EXPLAINER_VIDEO_FAKE_LOG, so a test asserts on what a stage asked for.
//   EXPLAINER_VIDEO_FAKE_PRESENT  comma-separated commands `which` finds
//   EXPLAINER_VIDEO_FAKE_PROBE    JSON fields overriding what ffprobe and
//                                 loudness answer
//   EXPLAINER_VIDEO_FAKE_CHECK    JSON check answers in place of its own
//   EXPLAINER_VIDEO_FAKE_CLIP_BYTES  size of each clip written (default 1000)
// The family `ubuntu` answers with its real, non-OFL licence.
//
// Fake audio is 16 kHz and spells its text: each letter holds 3 frames of 320
// samples (2 at the letter's vocabulary id / 100, 1 silent), each word ends on
// a `|` frame and 2 silent frames, each sentence on 10 more. The fake aligner
// reads a frame's id back from its first sample, so word timings come out of
// the real Viterbi pass. A sentence naming a marker word misrenders:
// `garbled` speaks every word as "mumble", `looped` speaks the sentence twice,
// `slowly` holds each letter 8 frames.
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

export async function fontMeta(id) {
  log({ call: "fontMeta", id });
  return {
    id,
    license: id === "ubuntu" ? "UFL-1.0" : "OFL-1.1",
    weights: [400, 600],
    subsets: ["latin"],
    styles: ["normal"],
  };
}

export async function download(url, file) {
  log({ call: "download", url });
  fs.writeFileSync(file, "woff2");
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

export async function synthesize({ text, narrator, tools }) {
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
  const samples = new Float32Array(frames.length * HOP);
  frames.forEach((id, f) => samples.fill(id / 100, f * HOP, (f + 1) * HOP));
  return { samples, sampleRate: 16000 };
}

export async function aligner() {
  const classes = Object.keys(VOCAB).length;
  return {
    vocab: VOCAB,
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

export async function master(input, output, { lufs, peak }) {
  log({ call: "master", input, output, lufs, peak });
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

// What shows at t: each mounted scene's own text elements, and the caption
// cue's words joined.
function showing(dir, t) {
  const html = fs.readFileSync(path.join(dir, "index.html"), "utf8");
  const on = (start, duration) => t >= +start && t < +start + +duration;
  const texts = [];
  for (const m of html.matchAll(
    /data-composition-id="([^"]+)" data-composition-src="[^"]+" data-start="([\d.]+)" data-duration="([\d.]+)"/g,
  ))
    if (on(m[2], m[3]))
      for (const e of fs
        .readFileSync(path.join(dir, "scenes", `${m[1]}.html`), "utf8")
        .matchAll(/<(?:div|span)[^>]*>([^<]+)</g))
        if (e[1].trim()) texts.push({ scene: m[1], text: e[1].trim() });
  for (const m of html.matchAll(
    /<div class="cue clip" data-start="([\d.]+)" data-duration="([\d.]+)"[^>]*>(.*?)<\/div>/g,
  ))
    if (on(m[1], m[2]))
      texts.push({ scene: null, text: m[3].replace(/<[^>]+>/g, "") });
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

export async function probe(dir, times) {
  log({ call: "probe", times });
  return times.map((t) => {
    const { html, texts } = showing(dir, t);
    const color = (k) => html.match(new RegExp(`--${k}: (#[0-9a-f]{6});`))[1];
    if (process.env.EXPLAINER_VIDEO_FAKE_BLANK) return { t, elements: [] };
    return {
      t,
      elements: texts.map(({ scene, text }, i) => {
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
        };
      }),
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
