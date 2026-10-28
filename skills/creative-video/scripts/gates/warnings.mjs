// The gates stage's advisory warnings: reported, never a refusal. Each is a
// `<name>: <detail>` line, over the plan (each scene's window), the probe's
// events (each scene's tween windows in its own seconds, and its sounds, judged
// in its own seconds by gates/sounds.mjs), the script, the cast, the sound kit
// and, for the clock scan, the project's scene and kit files.
import fs from "node:fs";
import path from "node:path";
import { sentences } from "../lib/length.mjs";
import { narrator as findNarrator } from "../lib/narrators.mjs";
import { sceneSeconds } from "./sounds.mjs";

// One of two places a gate reads scene code (ADR 0019), the other the sounds
// gate's read of each <audio> start: a clock or random read may
// break determinism, which the frames judge, so it is named, never refused.
const CLOCK = [
  ["Math.random", /Math\.random\b/],
  ["Date.now", /Date\.now\b/],
  ["new Date", /new Date\b/],
  ["performance.now", /performance\.now\b/],
  ["setTimeout", /\bsetTimeout\b/],
  ["setInterval", /\bsetInterval\b/],
  ["requestAnimationFrame", /\brequestAnimationFrame\b/],
];

// The files of `dir` in the project (captions.html is generated, not authored).
const listed = (proj, dir) =>
  fs.existsSync(path.join(proj, dir))
    ? fs
        .readdirSync(path.join(proj, dir), { withFileTypes: true })
        .filter((e) => e.isFile() && e.name !== "captions.html")
        .map((e) => `${dir}/${e.name}`)
        .sort()
    : [];

// More than 24 sounds in any minute of the video.
function effectRate(sounds) {
  let busiest = { n: 0, t: 0 };
  for (const t of sounds) {
    const n = sounds.filter((o) => o >= t && o < t + 60).length;
    if (n > busiest.n) busiest = { n, t };
  }
  return busiest.n > 24
    ? [
        `effect rate: ${busiest.n} sounds in the minute from ${busiest.t.toFixed(2)} s, over 24 a minute`,
      ]
    : [];
}

// A sound more than 0.15 s from its scene's nearest tween start.
function effectOnset({ sc }, { tweens, sounds }) {
  return sounds.flatMap((sound) => {
    const at = sceneSeconds(sc, sound);
    const gap = Math.min(...tweens.map(([from]) => Math.abs(at - from)));
    return tweens.length && gap > 0.15 + 1e-6
      ? [
          `effect onset: ${sc.id}: the sound at ${at.toFixed(2)} s is ${gap.toFixed(2)} s from the nearest tween start`,
        ]
      : [];
  });
}

// A dead stretch: 2 s or more with no tween running, in video seconds.
function deadStretches({ sc }, { tweens }) {
  const dead = [];
  let at = 0;
  for (const [from, to] of [...tweens]
    .sort((x, y) => x[0] - y[0])
    .concat([[sc.duration, sc.duration]])) {
    if (from - at >= 2)
      dead.push(
        `dead ${(sc.start + at).toFixed(2)}-${(sc.start + from).toFixed(2)} s in ${sc.id}`,
      );
    at = Math.max(at, to);
  }
  return dead;
}

const longSentences = (script) =>
  script.scenes.flatMap((s) =>
    s.narration.flatMap((line) =>
      sentences(line).flatMap((sentence) => {
        const words = sentence.split(/\s+/).filter(Boolean);
        return words.length > 25
          ? [
              `sentences: ${s.id}: "${words.slice(0, 5).join(" ")}..." is ${words.length} words, over 25`,
            ]
          : [];
      }),
    ),
  );

// Two roles a viewer cannot tell apart in the script's language: those of
// `cast` (cast.json, or null) and the narrator role it leaves out, which speaks
// script.json's `narrator`, else the language's default. Each pair speaks one
// narrator, and on Gemini, the one backend that acts the style line, one style
// line too.
function alikeVoices(cast, { language, narrator }) {
  const voiced = Object.entries(cast ?? {}).map(([role, c]) => ({
    role,
    // A missing id would find the language's default.
    n: c.voices[language] && findNarrator(c.voices[language], language),
    style: c.style,
  }));
  if (!cast?.narrator)
    voiced.unshift({ role: "narrator", n: findNarrator(narrator, language) });
  const roles = voiced
    .filter((r) => r.n)
    .map(({ role, n, style }) => ({
      role,
      id: n.id,
      acts: n.backend === "gemini",
      style: style ?? n.style,
    }));
  return roles.flatMap((a, i) =>
    roles
      .slice(i + 1)
      .filter((b) => b.id === a.id && (!a.acts || b.style === a.style))
      .map(
        (b) =>
          `alike voices: ${a.role} and ${b.role} both speak ${a.id}${a.acts ? " in the same style" : ""}`,
      ),
  );
}

// Each sound sound/sounds.mjs found nowhere and dropped from `sound`
// (sound.json, or null).
const droppedSounds = (sound) =>
  (sound?.dropped ?? []).map((d) => `dropped sound: ${d.event}: ${d.why}`);

const clockReads = (proj) =>
  [...listed(proj, "compositions"), ...listed(proj, "kit")].flatMap((f) => {
    const code = fs.readFileSync(path.join(proj, f), "utf8");
    const found = CLOCK.filter(([, re]) => re.test(code)).map(([name]) => name);
    return found.length ? [`clock: ${f} reads ${found.join(", ")}`] : [];
  });

// The warnings in print order, as `<name>: <detail>` lines. `total` is the
// video's length in seconds, `proj` the project folder, `cast` and `sound` its
// kit/cast.json and kit/sound.json or null.
export function warnings({ plan, events, script, cast, sound, total, proj }) {
  const eventsOf = (id) => events[id] ?? { tweens: [], sounds: [] };
  const sounds = plan.flatMap((p) =>
    eventsOf(p.sc.id).sounds.map((s) => p.sc.start + sceneSeconds(p.sc, s)),
  );
  const out = effectRate(sounds);
  let starts = 0;
  const dead = [];
  for (const p of plan) {
    const own = eventsOf(p.sc.id);
    starts += own.tweens.length;
    out.push(...effectOnset(p, own));
    if (p.sc.duration > 30)
      out.push(
        `scene length: ${p.sc.id}: ${p.sc.duration.toFixed(1)} s, over 30 s`,
      );
    dead.push(...deadStretches(p, own));
  }
  out.push(
    ...longSentences(script),
    ...alikeVoices(cast, script),
    ...droppedSounds(sound),
    `pacing: ${((starts + sounds.length) / (total / 60)).toFixed(1)} change events a minute; ${dead.join("; ") || "no dead stretch"}`,
    ...clockReads(proj),
  );
  return [...new Set(out)];
}
