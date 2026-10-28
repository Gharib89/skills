// A chapter's own HyperFrames project, <run>/.cache/render/chapter-<n>/, which
// the render stage renders to that chapter's video part: the root of only that
// chapter's scene hosts and its caption cues with every time counted from the
// chapter's first frame, no narration and no over.html (the one audio pass of
// the whole project carries every sound), a timing.js of that chapter's scenes
// on the same clock, a captions.html of its shifted cues, and symlinks to the
// project's scene files, kit/ and assets/, so a scene's own script runs as it
// does in the whole.
import fs from "node:fs";
import path from "node:path";
import { hashFiles, walk } from "../gates/inputs.mjs";
import { readJson } from "../lib/json.mjs";
import { lockHash } from "../lib/tools.mjs";
import { FPS, written } from "./grid.mjs";
import { captionsHtml, r3, timingJs, timingScenes } from "./project.mjs";
import { captionsHost, host, rootHtml } from "./root.mjs";

export const chapterDir = (run, n) =>
  path.join(path.resolve(run), ".cache", "render", `chapter-${n}`);

// Writes chapter `n`'s folder afresh from the run's `timeline` and `voice` and
// returns `{ dir, seconds, key }`: `seconds` is the chapter's length on the
// grid, `key` the 16 hex digits of a hash over every file the folder loads (its
// index.html, timing.js, captions.html, its scene files, kit/ and assets/), so
// a part rendered from it is reusable exactly while nothing it loads changed.
// The narration WAV and the HyperFrames CLI's own state are no input of a
// video-only render, and the lockfile hash stands for the HyperFrames engine.
export function writeChapter(run, { timeline, voice }, n) {
  const ch = timeline.chapters[n - 1];
  const { language } = readJson(run, "script.json");
  const proj = path.join(path.resolve(run), "project");
  const dir = chapterDir(run, n);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(path.join(dir, "compositions"), { recursive: true });
  const frame = (t) => Math.round(t * FPS);
  const by = frame(ch.start);
  const seconds = written(frame(ch.end) - by);
  const scenes = timeline.scenes.filter((s) => ch.scenes.includes(s.id));
  const cues = timeline.cues
    .filter((c) => c.start >= ch.start - 1e-6 && c.start < ch.end - 1e-6)
    .map((c) => ({
      ...c,
      start: r3(c.start - ch.start),
      end: r3(c.end - ch.start),
    }));

  for (const s of scenes)
    fs.symlinkSync(
      path.join(proj, "compositions", `${s.id}.html`),
      path.join(dir, "compositions", `${s.id}.html`),
    );
  for (const folder of ["assets", "kit"])
    if (fs.existsSync(path.join(proj, folder)))
      fs.symlinkSync(path.join(proj, folder), path.join(dir, folder));
  fs.writeFileSync(
    path.join(dir, "timing.js"),
    timingJs(
      seconds,
      timingScenes(scenes, voice, (s) => written(frame(s.start) - by)),
    ),
  );
  fs.writeFileSync(
    path.join(dir, "compositions", "captions.html"),
    captionsHtml(cues),
  );
  fs.writeFileSync(
    path.join(dir, "index.html"),
    rootHtml({
      proj: dir,
      title: `${path.basename(path.resolve(run))} chapter ${n}`,
      language,
      total: seconds,
      hosts: [
        ...scenes.map((s) =>
          host(s.id, written(frame(s.start) - by), s.duration, 1, "graphics"),
        ),
        captionsHost(seconds),
      ],
      narration: false,
    }),
  );
  return { dir, seconds, key: chapterKey(dir) };
}

// The 16 hex digits of the hash over the files a chapter folder loads.
function chapterKey(dir) {
  const files = walk(dir)
    .filter((f) => {
      const rel = path.relative(dir, f);
      return (
        rel.split(path.sep)[0] !== ".hyperframes" &&
        rel !== path.join("assets", "narration.wav")
      );
    })
    .sort();
  return hashFiles(dir, files, lockHash);
}
