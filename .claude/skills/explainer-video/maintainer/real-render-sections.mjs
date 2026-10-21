// Maintainer only: the sections checks of maintainer/real-render.mjs. A video in
// sections renders each section video only and joins the parts by stream copy;
// the real tools must give it the whole render's frames, the captions on its
// frames, one audio track and the chapter marks (checks `sections frames`,
// `sections captions`, `sections audio` and `sections chapters`).
import { spawnSync } from "node:child_process";
import path from "node:path";
import { meanDiff } from "../scripts/lib/motion.mjs";

const title = (section, id, role, seconds, narration) => ({
  seconds,
  scene: {
    id,
    role,
    section,
    title: `Scene ${id}`,
    narration,
    visual: {
      component: "title",
      props: { kicker: `Section ${section}`, title: `Scene ${id}` },
    },
  },
});

// Three sections, the hook in the first. Seconds are not whole frames, as in
// FIXTURE, so the padding is exercised.
export const SECTIONED = [
  title(1, "hook", "hook", 2.37, ["One run, one merge."]),
  title(1, "one", "section", 1.91, ["The first section opens."]),
  title(1, "one-a", "point", 2.13, ["It reads the issue.", "Then it plans."]),
  title(2, "two", "section", 1.77, ["The second section opens."]),
  title(2, "two-a", "point", 2.04, ["It writes the change."]),
  title(3, "three", "section", 1.83, ["The third section opens."]),
  title(3, "three-a", "point", 2.21, ["It merges.", "Then it is done."]),
];

// The caption band of the frame at `t`: 104 px in grey from y 908.
const band = (file, t) =>
  spawnSync(
    "ffmpeg",
    [
      ...["-v", "error", "-ss", String(t), "-i", file, "-frames:v", "1"],
      ...["-vf", "crop=1920:104:0:908,format=gray", "-f", "rawvideo", "-"],
    ],
    { maxBuffer: 1 << 26 },
  ).stdout;
// Caption pixels are light on dark, or the reverse: a band with ink is not flat.
const inked = (b) => {
  let [lo, hi] = [255, 0];
  for (const v of b) [lo, hi] = [Math.min(lo, v), Math.max(hi, v)];
  return hi - lo > 60;
};

// One cue a scene, its words every 0.3 s from 0.2 s in, as `compose` times them.
const cuesOf = (part, timeline) =>
  part.map((p, i) => {
    const words = p.scene.narration.join(" ").split(/\s+/);
    const tokens = words.map((text, k) => ({
      text,
      start: +(timeline[i].start + 0.2 + 0.3 * k).toFixed(3),
    }));
    return {
      text: words.join(" "),
      tokens,
      start: tokens[0].start,
      end: +(timeline[i].start + timeline[i].duration).toFixed(3),
    };
  });

// `compose(name, part, hold, page)` and `render(comp, out)` are
// real-render.mjs's own; `page(timeline)` adds to the composition's page.
export async function sectionChecks({
  compose,
  render,
  framemd5,
  check,
  backend,
  work,
}) {
  const extra = (part, audio) => (timeline) => ({
    audio,
    cues: cuesOf(part, timeline),
  });
  const whole = await compose(
    "sections-whole",
    SECTIONED,
    true,
    extra(SECTIONED, true),
  );
  const wholeMp4 = path.join(work, "sections-whole.mp4");
  let rendered = await render(whole.comp, wholeMp4);
  const numbers = [...new Set(SECTIONED.map((p) => p.scene.section))];
  const parts = [];
  for (const n of numbers) {
    const part = SECTIONED.filter((p) => p.scene.section === n);
    const c = await compose(
      `section-${n}`,
      part,
      n === numbers.at(-1),
      extra(part, false),
    );
    const mp4 = path.join(work, `section-${n}.mp4`);
    rendered = (await render(c.comp, mp4)) && rendered;
    parts.push({ ...c, mp4 });
  }
  if (!rendered) return check("sections frames", false, "a render failed");

  const chapters = numbers.map((n, k) => {
    const i = SECTIONED.findIndex(
      (p) => p.scene.section === n && p.scene.role === "section",
    );
    const next = SECTIONED.findIndex(
      (p) => p.scene.section === numbers[k + 1] && p.scene.role === "section",
    );
    return {
      start: whole.scenes[i].start,
      end: whole.scenes[next]?.start ?? +(whole.frames / 30).toFixed(3),
      title: SECTIONED[i].scene.title,
    };
  });
  const video = path.join(work, "sections-joined-video.mp4");
  const joined = path.join(work, "sections-joined.mp4");
  await backend.concat(
    parts.map((p) => p.mp4),
    video,
  );
  await backend.mux({
    video,
    audio: path.join(whole.comp, "narration.wav"),
    chapters,
    output: joined,
  });

  const [a, b] = [framemd5(joined).length, framemd5(wholeMp4).length];
  check(
    "sections frames",
    a === b && a === whole.frames,
    `${a} frames joined, ${b} in the whole render, ${whole.frames} on the composer's grid`,
  );

  // The second scene of each section, 0.5 s in: a cue is showing, and the
  // joined file's band matches the whole render's within an encode's noise.
  const apart = numbers.map((n) => {
    const k = SECTIONED.findIndex((p) => p.scene.section === n) + 1;
    const t = whole.scenes[k].start + 0.5;
    const [j, w] = [band(joined, t), band(wholeMp4, t)];
    return { inked: inked(j), diff: meanDiff(j, w) };
  });
  check(
    "sections captions",
    apart.every((x) => x.inked && x.diff <= 12),
    `caption bands of ${apart.length} sections: ${apart.map((x) => `${x.inked ? "inked" : "flat"} diff ${x.diff.toFixed(1)}`).join(", ")} (inked, diff <= 12 expected)`,
  );

  const audio = (f) =>
    backend
      .ffprobe(f)
      .then((p) => p.streams.filter((s) => s.codec_type === "audio"));
  const own = await Promise.all(parts.map((p) => audio(p.mp4)));
  const mixed = await audio(joined);
  check(
    "sections audio",
    own.every((s) => s.length === 0) &&
      mixed.length === 1 &&
      mixed[0].codec_name === "aac",
    `${own.map((s) => s.length).join("+")} audio streams in the parts, ${mixed.length} in the joined file (${mixed[0]?.codec_name ?? "none"}; 0+0+0 and 1 aac expected)`,
  );

  const marks = (await backend.ffprobe(joined)).chapters ?? [];
  check(
    "sections chapters",
    marks.length === chapters.length &&
      marks.every(
        (m, k) =>
          Math.abs(+m.start_time - chapters[k].start) <= 1 / 30 &&
          m.tags?.title === chapters[k].title,
      ),
    `${marks.map((m) => `${(+m.start_time).toFixed(2)} s ${m.tags?.title}`).join(", ")} (${chapters.map((c) => `${c.start.toFixed(2)} s ${c.title}`).join(", ")} expected)`,
  );
}
