// What the render stage reads off a finished video and where it delivers it.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { explainersDir, isPart } from "../lib/runfolder.mjs";
import { skill } from "../lib/tools.mjs";

const clock = (t) => {
  const ms = Math.round(t * 1000);
  const pad = (n, w = 2) => String(n).padStart(w, "0");
  return `${pad(Math.floor(ms / 3600000))}:${pad(Math.floor(ms / 60000) % 60)}:${pad(Math.floor(ms / 1000) % 60)},${pad(ms % 1000, 3)}`;
};

// The caption cues as an SRT file's text.
export const srtText = (cues) =>
  cues
    .map(
      (c, i) => `${i + 1}\n${clock(c.start)} --> ${clock(c.end)}\n${c.text}\n`,
    )
    .join("\n");

// manifest.json: `facts` after the board's link, which a render keeps, and the
// skill's version.
export function writeManifest(run, facts) {
  const file = path.join(run, "manifest.json");
  const old = fs.existsSync(file)
    ? JSON.parse(fs.readFileSync(file, "utf8"))
    : {};
  const version = fs
    .readFileSync(path.join(skill, "SKILL.md"), "utf8")
    .match(/^ {2}version: (\S+)$/m)[1];
  fs.writeFileSync(
    file,
    JSON.stringify(
      { board: old.board ?? null, skill: version, ...facts },
      null,
      2,
    ) + "\n",
  );
}

// The videos folder's repo name for a run folder: a worktree's is its main
// repo's. A submodule's or a separate git dir's common dir is no
// `<repo>/.git`, so those take their top level's name.
export function repoName(run) {
  const git = spawnSync(
    "git",
    [
      ...["-C", run, "rev-parse", "--path-format=absolute"],
      ...["--git-common-dir", "--show-toplevel"],
    ],
    { encoding: "utf8" },
  );
  const [common, top] = git.stdout.trim().split("\n");
  return git.status !== 0
    ? path.basename(path.dirname(explainersDir(run)))
    : path.basename(common) === ".git"
      ? path.basename(path.dirname(common))
      : path.basename(top);
}

// Copies a run's video, captions and poster from `out` into the videos folder
// under the repo's name and returns that folder. A part goes into its series'
// folder, so the numbered parts sit side by side, its poster named after it.
export function deliver(run, out, slug, videos) {
  const part = isPart(run)
    ? JSON.parse(fs.readFileSync(path.join(run, "part.json"), "utf8"))
    : null;
  const to = path.join(
    videos,
    "explainer-video",
    repoName(run),
    part ? part.series : slug,
  );
  fs.mkdirSync(to, { recursive: true });
  for (const [from, as] of [
    [`${slug}.mp4`, `${slug}.mp4`],
    [`${slug}.srt`, `${slug}.srt`],
    ["poster.png", part ? `${slug}.png` : "poster.png"],
  ])
    fs.copyFileSync(path.join(out, from), path.join(to, as));
  return to;
}

// The video stream's size, frame rate and aspect ratio from ffprobe's answer.
export function videoFacts(probe) {
  const vs = probe.streams.find((s) => s.codec_type === "video") ?? {};
  const [num, den = 1] = String(vs.r_frame_rate ?? "0/1")
    .split("/")
    .map(Number);
  const gcd = (a, b) => (b ? gcd(b, a % b) : a);
  const ratio =
    vs.display_aspect_ratio && vs.display_aspect_ratio !== "0:1"
      ? vs.display_aspect_ratio
      : `${vs.width / gcd(vs.width, vs.height)}:${vs.height / gcd(vs.width, vs.height)}`;
  return {
    size: `${vs.width}x${vs.height}`,
    fps: +(num / den).toFixed(3),
    ratio,
  };
}
