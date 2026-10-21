// A video in sections, for the render stage. Each section renders video only,
// in a composition of its own with every time counted from its own start, so
// an edit to one scene changes only its section's cache key. The parts join at
// the hard cuts by stream copy, and the narration and score are encoded once
// on the joined file, which takes a chapter mark per section at its opener's
// first frame. Hook and context sit in the first section, recap and end in the
// last (script/compile.mjs numbers them so).
import fs from "node:fs";
import path from "node:path";
import { FPS, videoPage } from "./compose.mjs";
import { captionCues } from "./cues.mjs";

const r3 = (n) => +n.toFixed(3);

// The sections of the script's scenes, in order: `{ number, at }`, `at` the
// scenes' indices. None for a video the compile stage did not cut.
export function sectionsOf(scenes) {
  const out = [];
  for (const [i, s] of scenes.entries()) {
    if (!s.section) continue;
    if (out.at(-1)?.number !== s.section)
      out.push({ number: s.section, at: [] });
    out.at(-1).at.push(i);
  }
  return out;
}

// Writes `sec`'s composition into `d`: the whole composition's fonts, scripts
// and scene files for its scenes, and a page of those scenes without the
// narration. `timeline` is the render's scenes by script index.
export function writeSection(d, { sec, comp, script, timeline, ...page }) {
  const first = timeline[sec.at[0]];
  const last = timeline[sec.at.at(-1)];
  const rel = (t) => r3(t - first.start);
  const own = sec.at.map((i) => ({
    ...timeline[i],
    start: rel(timeline[i].start),
    words: timeline[i].words.map((w) => ({
      ...w,
      start: rel(w.start),
      end: rel(w.end),
    })),
  }));
  fs.mkdirSync(path.join(d, "scenes"), { recursive: true });
  fs.cpSync(path.join(comp, "fonts"), path.join(d, "fonts"), {
    recursive: true,
  });
  for (const f of ["gsap.min.js", ...(page.webgl ? ["three.min.js"] : [])])
    fs.copyFileSync(path.join(comp, f), path.join(d, f));
  for (const i of sec.at) {
    const f = path.join("scenes", `${script.scenes[i].id}.html`);
    fs.copyFileSync(path.join(comp, f), path.join(d, f));
  }
  fs.writeFileSync(
    path.join(d, "index.html"),
    videoPage({
      ...page,
      title: script.title,
      scenes: own,
      cues: captionCues(
        sec.at.map((i) => script.scenes[i]),
        own,
      ),
      total: rel(last.start + last.duration),
      audio: false,
    }),
  );
}

// One chapter per section: its opener's title from the opener's first frame to
// the next opener's, the last to the video's end.
export function chaptersOf(sections, script, timeline, total) {
  const opens = sections.map((sec) =>
    sec.at.find((i) => script[i].role === "section"),
  );
  return opens.map((i, k) => ({
    start: timeline[i].start,
    end: timeline[opens[k + 1]]?.start ?? total,
    title: script[i].title,
  }));
}

// The section `parts` joined by stream copy into `joined`, then muxed with the
// narration and `chapters` into `output`; `joined` is removed after.
export async function joinSections(
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
