// Canned media tools: the render, ffprobe, loudness, clips, sheets and frames.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { sceneFrames } from "../../skills/explainer-video/scripts/lib/motion.mjs";
import { showing } from "./fake-backend-gates.mjs";
import { log } from "./fake-backend-log.mjs";

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

// A sheet's bytes follow its scene's own HTML, as the real frames do, and not
// where the scene sits in the video.
export async function sheet(input, output, { start, duration, fps, fullest }) {
  log({ call: "sheet", input, output, start, duration, fps, fullest });
  const id = path.basename(output, ".png");
  const html = fs.readFileSync(
    path.join(path.dirname(input), "..", "composition", "scenes", `${id}.html`),
  );
  const own = crypto.createHash("sha256").update(html).digest("hex");
  fs.writeFileSync(output, `sheet of ${id} ${own} ${fullest}`);
}

export async function strip(input, output, { first, fps }) {
  log({ call: "strip", input, output, first, fps });
  fs.writeFileSync(output, `strip of ${path.basename(output, ".motion.png")}`);
}

// A scene moves unless its start is listed in EXPLAINER_VIDEO_FAKE_STILL (a JSON
// array of seconds): a moving one differs by 1 a frame and by 9 at frame n/3, a
// still one not at all. EXPLAINER_VIDEO_FAKE_MOTION is a JSON object of start
// seconds to the scene's own differences, for a test that places a peak.
export async function bandMotion(input, { start, duration, fps }) {
  log({ call: "bandMotion", input, start, duration, fps });
  const { n } = sceneFrames({ start, duration, fps });
  const own = JSON.parse(process.env.EXPLAINER_VIDEO_FAKE_MOTION ?? "{}")[
    start
  ];
  if (own) return own;
  const still = JSON.parse(process.env.EXPLAINER_VIDEO_FAKE_STILL ?? "[]");
  const diffs = Array(n - 1).fill(still.includes(start) ? 0 : 1);
  if (!still.includes(start)) diffs[Math.floor(n / 3)] = 9;
  return diffs;
}

// One frame of the composition: what shows at t as a pixels line, then a
// metadata line that differs on every call, which a hash of the pixels must not
// read. An element naming `flaky` draws differently each time it is rendered.
export async function frame(dir, t, out) {
  log({ call: "frame", t, out });
  const renders = fs
    .readFileSync(process.env.EXPLAINER_VIDEO_FAKE_LOG, "utf8")
    .split("\n")
    .filter((l) => l.includes('"call":"frame"')).length;
  const { texts } = showing(dir, t);
  const flaky = texts.some((e) => /\bflaky\b/.test(e.text));
  fs.writeFileSync(
    out,
    `pixels: ${texts.map((e) => e.text).join("|")}${flaky ? ` #${renders}` : ""}\nmeta: render ${renders}\n`,
  );
}

export async function framePixels(file) {
  const line = fs.readFileSync(file, "utf8").split("\n")[0];
  return crypto.createHash("sha256").update(line).digest("hex");
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
