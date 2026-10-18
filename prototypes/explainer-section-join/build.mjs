// PROTOTYPE: cuts the first 12 scenes of dora-core's composition (hook to
// infra, 313.885 s) into a whole composition and three sections opened by
// hook, structure and flow, in two timings:
//   naive/   scenes as the composer times them; a section shifted by its start
//   snapped/ every scene's duration rounded up to whole frames, so each
//            section starts on a frame boundary
// Each mode gets whole/ (with the narration) and s1/ s2/ s3/ (video only).
// usage: node build.mjs <dora-core composition dir> <work dir>
import fs from "node:fs";
import path from "node:path";

const [src, work] = process.argv.slice(2);
const FPS = 30;
const LAST = "infra";
const OPENERS = ["hook", "structure", "flow"];
const html = fs.readFileSync(path.join(src, "index.html"), "utf8");
const r6 = (x) => +x.toFixed(6);
// Truncated, never rounded up: HyperFrames renders ceil(duration * fps) frames,
// so a duration of whole frames written a hair long gains a frame.
const t6 = (x) => Math.floor(x * 1e6 + 1e-4) / 1e6;

const hostRe =
  /<div id="scene-(\w+)"[^>]*data-start="([\d.]+)" data-duration="([\d.]+)"[^>]*><\/div>/g;
const all = [...html.matchAll(hostRe)].map((m) => ({
  id: m[1],
  start: +m[2],
  duration: +m[3],
  tag: m[0],
}));
const scenes = all.slice(0, all.findIndex((s) => s.id === LAST) + 1);
const END = scenes.at(-1).start + scenes.at(-1).duration;
const cueRe = /<div class="cue clip" data-start="([\d.]+)"[^\n]*<\/div>/g;
const cues = [...html.matchAll(cueRe)]
  .map((m) => ({ start: +m[1], tag: m[0] }))
  .filter((c) => c.start < END - 1e-6);

const head = html.slice(0, html.indexOf('<div id="scene-'));
const tail = html.slice(html.lastIndexOf("<script>"));

// The scene a time falls in, by its original start.
const sceneAt = (t) => scenes.findLast((s) => s.start <= t + 1e-6);

function timing(mode) {
  let at = 0;
  return scenes.map((s) => {
    const d =
      mode === "snapped"
        ? Math.ceil(s.duration * FPS - 1e-6) / FPS
        : s.duration;
    const t = { ...s, start2: at, duration2: d, shift: at - s.start };
    at += d;
    return t;
  });
}

function page({ timed, from, to, audio, total }) {
  const pick = timed.filter(
    (s) => s.start2 >= from - 1e-6 && s.start2 < to - 1e-6,
  );
  const shiftOf = (t) => timed.find((s) => s.id === sceneAt(t).id).shift;
  const hosts = pick.map((s) =>
    s.tag
      .replace(`data-start="${s.start}"`, `data-start="${t6(s.start2 - from)}"`)
      .replace(
        `data-duration="${s.duration}"`,
        `data-duration="${t6(s.duration2)}"`,
      ),
  );
  const lines = cues
    .filter((c) => {
      const t = c.start + shiftOf(c.start);
      return t >= from - 1e-6 && t < to - 1e-6;
    })
    .map((c) => {
      const k = shiftOf(c.start) - from;
      return c.tag.replace(
        /data-(start|at)="([\d.]+)"/g,
        (_, a, v) => `data-${a}="${r6(+v + k)}"`,
      );
    });
  return (
    head.replace(/data-duration="[\d.]+"/, `data-duration="${t6(total)}"`) +
    hosts.map((h) => `      ${h}\n`).join("") +
    `      <div class="captions">\n${lines.map((l) => `        ${l}\n`).join("")}      </div>\n` +
    (audio
      ? `      <audio id="narration" src="narration.wav" data-start="0" data-duration="${t6(total)}" data-track-index="3" data-volume="1"></audio>\n`
      : "") +
    "    </div>\n    " +
    tail
  );
}

// The narration as PCM: the whole video's samples, each scene padded with
// silence to its snapped duration.
const wav = fs.readFileSync(path.join(src, "narration.wav"));
const dataAt = wav.indexOf("data") + 8;
const rate = wav.readUInt32LE(24);
const block = wav.readUInt16LE(32);
const pcm = wav.subarray(dataAt, dataAt + wav.readUInt32LE(dataAt - 4));
function narration(timed, file) {
  const parts = timed.map((s) => {
    const a = Math.round(s.start * rate) * block;
    const n = Math.round(s.duration * rate) * block;
    const want = Math.round(s.duration2 * rate) * block;
    return Buffer.concat([pcm.subarray(a, a + n), Buffer.alloc(want - n)]);
  });
  const data = Buffer.concat(parts);
  // A plain 44-byte header: the fmt chunk copied, the source's LIST dropped.
  const h = Buffer.concat([
    Buffer.from("RIFF0000WAVE", "ascii"),
    wav.subarray(12, 36),
    Buffer.from("data0000", "ascii"),
  ]);
  h.writeUInt32LE(36 + data.length, 4);
  h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(file, Buffer.concat([h, data]));
}

const plan = {};
for (const mode of ["naive", "snapped"]) {
  const timed = timing(mode);
  const total = timed.at(-1).start2 + timed.at(-1).duration2;
  const bounds = OPENERS.map((id) => timed.find((s) => s.id === id).start2);
  bounds.push(total);
  const dirs = [
    { name: "whole", from: 0, to: total, audio: true },
    ...OPENERS.map((_, i) => ({
      name: `s${i + 1}`,
      from: bounds[i],
      to: bounds[i + 1],
      audio: false,
    })),
  ];
  for (const d of dirs) {
    const dir = path.join(work, mode, d.name);
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
    for (const f of ["fonts", "scenes", "gsap.min.js"])
      fs.cpSync(path.join(src, f), path.join(dir, f), { recursive: true });
    fs.writeFileSync(
      path.join(dir, "index.html"),
      page({
        timed,
        from: d.from,
        to: d.to,
        audio: d.audio,
        total: d.to - d.from,
      }),
    );
    if (d.audio) narration(timed, path.join(dir, "narration.wav"));
  }
  plan[mode] = {
    total: r6(total),
    sections: OPENERS.map((id, i) => ({
      opener: id,
      start: r6(bounds[i]),
      duration: r6(bounds[i + 1] - bounds[i]),
      startFrames: r6(bounds[i] * FPS),
      frames: Math.ceil(t6(bounds[i + 1] - bounds[i]) * FPS),
    })),
    scenes: timed.map((s) => ({
      id: s.id,
      start: s.start2,
      duration: s.duration2,
    })),
  };
}
fs.writeFileSync(
  path.join(work, "plan.json"),
  JSON.stringify(plan, null, 2) + "\n",
);
console.log(
  JSON.stringify(
    Object.fromEntries(
      Object.entries(plan).map(([k, v]) => [
        k,
        { total: v.total, sections: v.sections },
      ]),
    ),
  ),
);
