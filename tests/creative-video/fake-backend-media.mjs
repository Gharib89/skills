// Canned media tools: the HyperFrames render, the join, the mux, ffprobe,
// loudness, loudnorm and the poster frame.
import fs from "node:fs";
import path from "node:path";
import { log } from "./fake-backend-log.mjs";

const stand = (f) => JSON.parse(fs.readFileSync(f, "utf8"));

// A `render` writes the JSON stand-in the fake ffprobe and loudness answer
// from: the root's duration at 1920x1080, 30 fps, with audio when the project
// holds an <audio>. Every other subcommand only logs.
export async function hyperframes(args, { cwd, env, stdio }) {
  log({
    call: "hyperframes",
    args,
    cwd,
    stdio: stdio ?? "quiet",
    env: Object.fromEntries(
      ["HYPERFRAMES_NO_TELEMETRY", "DO_NOT_TRACK", "HOME"].map((k) => [
        k,
        env[k] ?? null,
      ]),
    ),
  });
  if (args[0] === "render") {
    const html = fs.readFileSync(path.join(cwd, "index.html"), "utf8");
    const duration = +html.match(
      /data-composition-id="main"[^>]*data-duration="([\d.]+)"/,
    )[1];
    fs.writeFileSync(
      args[args.indexOf("-o") + 1],
      JSON.stringify({
        width: 1920,
        height: 1080,
        fps: 30,
        duration,
        audio: html.includes("<audio"),
        lufs: -14.0,
        peak: -1.6,
      }),
    );
  }
  return 0;
}

// Integrated loudness and true peak, from the fake video's file as ffprobe.
export async function loudness(file) {
  const v = {
    ...stand(file),
    ...JSON.parse(process.env.CREATIVE_VIDEO_FAKE_PROBE ?? "{}"),
  };
  log({ call: "loudness", file });
  return { lufs: v.lufs ?? -14.0, peak: v.peak ?? -1.6 };
}

export async function loudnorm(input, output, { lufs, peak }) {
  log({ call: "loudnorm", input, output, lufs, peak });
  fs.copyFileSync(input, output);
}

export async function poster(video, seconds, png) {
  log({ call: "poster", video, seconds, png });
  fs.writeFileSync(png, "poster");
}

// Stream-copy join of the fake parts: their durations add, and the audio the
// parts do not carry stays out.
export async function concat(parts, output) {
  log({ call: "concat", parts, output });
  const all = parts.map(stand);
  fs.writeFileSync(
    output,
    JSON.stringify({
      ...all[0],
      duration: +all.reduce((t, p) => t + p.duration, 0).toFixed(3),
    }),
  );
}

// The one mux: the video's stand-in with audio and the chapters written.
export async function mux({ video, audio, chapters, output }) {
  log({ call: "mux", video, audio, chapters, output });
  fs.writeFileSync(
    output,
    JSON.stringify({ ...stand(video), audio: true, chapters }),
  );
}

// Answers from the fake part's file, each field overridable through
// CREATIVE_VIDEO_FAKE_PROBE (JSON), as ffprobe's -show_streams -show_format
// -show_chapters.
export async function ffprobe(file) {
  const v = {
    ...JSON.parse(fs.readFileSync(file, "utf8")),
    ...JSON.parse(process.env.CREATIVE_VIDEO_FAKE_PROBE ?? "{}"),
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
    chapters: (v.chapters ?? []).map((c) => ({
      start_time: String(c.start),
      end_time: String(c.end),
      tags: { title: c.title },
    })),
  };
}
