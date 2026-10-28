// A video in chapters, for the render stage. Each chapter renders video only,
// so an edit to one scene changes only its chapter's render. The chapter
// renders join at the hard cuts by stream copy, and the narration is encoded once on the
// joined file, which takes a chapter mark per chapter at its first frame. The
// plan (script.json's `chapters`) is held to the scenes and the grid here.
import fs from "node:fs";
import { CHAPTER_SECONDS } from "../lib/length.mjs";
import { FPS, written } from "./grid.mjs";

// The timeline's chapters, `{ n, title, start, end, scenes }` on the frame grid,
// from the plan `chapters` (`{ title, scenes }`), the script's scene `ids` and
// the scenes' `grid` (render/grid.mjs's gridScenes). `fail(why)` stops the
// run on a plan that leaves a scene out, names one twice or not at all, runs
// out of scene order (which also covers a chapter that is not contiguous), has
// a blank title or no scenes, or runs over 6 minutes within 10 percent, or,
// with two or more chapters, under 2. A lone chapter has no minimum: it is a
// video that is not long.
export function planChapters(chapters, ids, grid, fail) {
  const seen = new Set();
  chapters.forEach((c, i) => {
    if (!c.title.trim()) fail(`chapter ${i + 1} has no title`);
    if (!c.scenes.length) fail(`chapter ${i + 1} "${c.title}" has no scenes`);
    for (const id of c.scenes) {
      if (!ids.includes(id))
        fail(`chapter ${i + 1} names scene ${id}, which script.json lacks`);
      if (seen.has(id)) fail(`scene ${id} is in two chapters`);
      seen.add(id);
    }
  });
  const lost = ids.find((id) => !seen.has(id));
  if (lost) fail(`scene ${lost} is in no chapter`);
  const listed = chapters.flatMap((c) => c.scenes);
  const off = ids.findIndex((id, i) => listed[i] !== id);
  if (off >= 0)
    fail(
      `chapters are not in scene order: found scene ${listed[off]} where script.json has ${ids[off]}`,
    );
  return chapters.map((c, i) => {
    const [first, last] = [c.scenes[0], c.scenes.at(-1)].map((id) =>
      grid.at(ids.indexOf(id)),
    );
    const [from, to] = [first.start, last.start + last.frames];
    const seconds = (to - from) / FPS;
    const [min, max] = CHAPTER_SECONDS;
    const lone = chapters.length === 1;
    if ((!lone && seconds < min) || seconds > max)
      fail(
        lone
          ? `chapter 1 "${c.title}" is ${seconds.toFixed(2)} s, over 6 minutes within 10% (${max} s): a video this long plans 2 or more chapters`
          : `chapter ${i + 1} "${c.title}" is ${seconds.toFixed(2)} s, outside 2 to 6 minutes within 10% (${min} to ${max} s)`,
      );
    return {
      n: i + 1,
      title: c.title,
      start: written(from),
      end: written(to),
      scenes: c.scenes,
    };
  });
}

// The chapter `parts` joined by stream copy into `joined`, then muxed with the
// narration and `chapters` into `output`; `joined` is removed after.
export async function joinChapters(
  backend,
  { parts, joined, audio, chapters, output },
) {
  try {
    await backend.concat(parts, joined);
    await backend.mux({ video: joined, audio, chapters, output });
  } finally {
    fs.rmSync(joined, { force: true });
  }
}

// The delivery check of the chapters: those ffprobe reads off the delivered
// file against `chapters`, each start within a frame and its title the same.
export function chapterCheck(chapters, probed = []) {
  const marks = (list) =>
    list.map((c) => `${(+c.start).toFixed(2)} s ${c.title}`).join(", ");
  const found = probed.map((c) => ({
    start: +c.start_time,
    title: c.tags?.title,
  }));
  return [
    "chapters",
    `${found.length} chapters${found.length ? ` (${marks(found)})` : ""}`,
    `${chapters.length} (${marks(chapters)})`,
    found.length === chapters.length &&
      found.every(
        (c, k) =>
          Math.abs(c.start - chapters[k].start) <= 1 / FPS &&
          c.title === chapters[k].title,
      ),
  ];
}
