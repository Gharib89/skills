// A video in chapters, for the render stage. Each chapter renders video only,
// so an edit to one scene changes only its chapter's part. The parts join at
// the hard cuts by stream copy, and the narration is encoded once on the
// joined file, which takes a chapter mark per chapter at its first frame.
import fs from "node:fs";
import { FPS } from "./grid.mjs";

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
