// Canned media tools: the join, the mux and ffprobe.
import fs from "node:fs";
import { log } from "./fake-backend-log.mjs";

const stand = (f) => JSON.parse(fs.readFileSync(f, "utf8"));

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
