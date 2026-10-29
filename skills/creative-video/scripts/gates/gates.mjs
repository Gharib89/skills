// The gates stage: the authored project judged on what it renders, before the
// full render (ADR 0019: output and narration, never scene code, but for the
// <audio> starts a scene file writes).
//
//   node gates.mjs <run-folder>
//
// Reads <run>/timeline.json, voice.json, script.json, brief.json (optional:
// `must` and `avoid` word lists), excerpts.json, claims.json, the critic's
// verdicts and <run>/project/. Samples each scene 0.3 s in, at its middle and
// on its last frame (gates/samples.mjs), and measures the samples with
// HyperFrames' check, a text probe (one launch, over the samples and a 0.25 s
// grid) and two snapshot launches. Thirteen gates judge the project, each a hard
// fail: determinism (the same pixels twice), layout, contrast, reading time,
// the caption band, anchors (an at() naming a word the narration lacks),
// script errors (a scene's script that throws), sounds (each <audio> renders
// at the start the gates judge, gates/sounds.mjs), licence and bed level (the
// sound kit, gates/sound-kit.mjs), must and avoid, support (the
// claims check passed on the voiced narration) and the critic
// (gates/critic.mjs), pending until each scene's verdict is written. Length,
// loudness and voice QC are the voice and render stages' own. A video in
// chapters adds two gates: chapter titles (each chapter's first frame draws
// every word of its title) and sound only (over.html draws no element, since a
// chapter renders without it). Advisory warnings
// (gates/warnings.mjs) never change the exit: effect rate, effect onset, scene
// length, sentences, alike voices, dropped sound, pacing and clock.
// stdout: `gate <name>: pass|fail|pending: <measured> vs <floor>` per gate (the
//         rest of a failing gate's findings indented under it), `warn <name>:
//         <detail>` per warning, then `gates: <n> pass, <m> fail[, 1 pending]`,
//         when red ending `; next: fix attempt <a> of 2` or, past two, `; stop:
//         red after two fix attempts, no video`, on a red second critic round
//         `; stop: the critic's second round is red, no video`, and with only
//         the critic left `; next: run the critic, round <r> of 2`
// writes: <run>/gates.json (the inputs and voice it is of, the attempts, each
//         gate's status, measured, floor and evidence, the warnings),
//         .cache/gates/frames/a and b, the critic's stills under
//         .cache/critic/<key>, and the root again (render/root.mjs)
// exit:   0 every gate passes · 1 a gate fails or the critic is pending, or
//         `gates: <why>` on stderr (the render's own refusals: no timeline, an
//         older voice, a missing scene file; a malformed critic verdict) ·
//         2 usage
import fs from "node:fs";
import path from "node:path";
import { claimsKey } from "../lib/claims.mjs";
import { maybeJson, readJson } from "../lib/json.mjs";
import { soundKit, voicedCast } from "../lib/kit.mjs";
import { readTimeline, writeIgnore } from "../lib/runfolder.mjs";
import { stage } from "../lib/stage.mjs";
import { hyperframesEnv, loadBackend } from "../lib/tools.mjs";
import { NO_WORD, NO_WORD_RE } from "../render/anchors.mjs";
import { HEIGHT, WIDTH, writeRoot } from "../render/root.mjs";
import { inputsHash } from "./inputs.mjs";
import { criticGate } from "./critic.mjs";
import { readable, readingFindings } from "./reading.mjs";
import { ceil3, sampleTimes } from "./samples.mjs";
import { BED_LU, bedLevel, licenceFindings } from "./sound-kit.mjs";
import { soundFindings } from "./sounds.mjs";
import { warnings } from "./warnings.mjs";

stage("gates");
const [run, ...rest] = process.argv.slice(2);
if (!run || rest.length) {
  console.error("usage: node gates.mjs <run-folder>");
  process.exit(2);
}
function fail(why) {
  console.error(`gates: ${why}`);
  process.exit(1);
}
async function orFail(call) {
  try {
    return await call();
  } catch (e) {
    return fail(e.message);
  }
}

// The floors: type of at least 18 px inside a margin of 5% of each side, the
// bottom 220 px left to the captions, at most two fix attempts.
const TEXT_PX = 18;
const MARGIN_X = Math.round(WIDTH * 0.05);
const MARGIN_Y = Math.round(HEIGHT * 0.05);
const BAND = HEIGHT - 220;
const MAX_ATTEMPTS = 2;

const { timeline, voice: voiced } = readTimeline(run, fail);
const script = readJson(run, "script.json");
const brief = maybeJson(run, "brief.json");
const prev = maybeJson(run, "gates.json");
writeIgnore(run);
writeRoot(run);
const inputs = inputsHash(run);
const proj = path.join(path.resolve(run), "project");
const backend = await loadBackend();
const env = hyperframesEnv();
const uniq = (ts) => [...new Set(ts)].sort((a, b) => a - b);

// Each scene's sample times, and the probe's 0.25 s grid over its length.
const plan = timeline.scenes.map((sc) => {
  const end = sc.start + sc.duration;
  const grid = [];
  for (let t = sc.start; t < end; t += 0.25) grid.push(ceil3(t));
  return { sc, end, samples: uniq(Object.values(sampleTimes(sc))), grid };
});
const sampled = uniq(plan.flatMap((p) => p.samples));
const sceneAt = (t) =>
  (plan.find((p) => t >= p.sc.start - 1e-6 && t < p.end) ?? plan.at(-1)).sc.id;
const sourceScene = (f) =>
  f.sourceFile?.match(/^compositions\/(.+)\.html$/)?.[1];
const sceneOf = (f) => sourceScene(f) ?? sceneAt(f.time);
const quote = (t) => `"${t.length > 40 ? `${t.slice(0, 40)}...` : t}"`;

const checked = await orFail(() => backend.check(proj, sampled, { env }));
// A check that never reached the browser answers {ok: false, error} alone.
for (const k of ["runtime", "layout", "contrast"])
  if (!checked[k])
    fail(`hyperframes check: ${checked.error ?? `no ${k} result`}`);
const { frames, events } = await orFail(() =>
  backend.probe(proj, uniq([...sampled, ...plan.flatMap((p) => p.grid)]), {
    env,
  }),
);
// A scene's own text at a probe time: the captions are drawn over every scene.
const sceneTexts = (f) => f.texts.filter((e) => e.scene !== "captions");
const textsAt = (t) => sceneTexts(frames.find((f) => f.t === t));

// Determinism: the sample frames rendered in two launches, compared by pixels.
fs.rmSync(path.join(run, ".cache", "gates", "frames"), {
  recursive: true,
  force: true,
});
const launch = (d) =>
  orFail(async () => {
    const taken = await backend.snapshot(
      proj,
      sampled,
      path.resolve(run, ".cache", "gates", "frames", d),
      { env },
    );
    return Promise.all(
      taken.map(async (f) => [
        f.time,
        await backend.framePixels(f.path),
        f.path,
      ]),
    );
  });
const [a, b] = [await launch("a"), await launch("b")];
if (a.length !== sampled.length || b.length !== sampled.length)
  fail(`snapshot gave ${a.length} and ${b.length} of ${sampled.length} frames`);
const determinism = a.flatMap(([t, pixels], i) =>
  pixels === b[i][1]
    ? []
    : [
        `${t.toFixed(2)} s ${sceneAt(t)}: the frame differs between two launches`,
      ],
);

// One defect held across several samples is one finding: its first time, and
// the number of samples it showed in.
function collect() {
  const seen = new Map();
  return {
    add(t, scene, what) {
      const hit = seen.get(`${scene}: ${what}`);
      if (hit) hit.n++;
      else seen.set(`${scene}: ${what}`, { t, scene, what, n: 1 });
    },
    lines: () =>
      [...seen.values()].map(
        ({ t, scene, what, n }) =>
          `${t.toFixed(2)} s ${scene}: ${what}${n > 1 ? ` (${n} samples)` : ""}`,
      ),
  };
}

// Layout: HyperFrames' errors, and the probe's readable text at the samples.
// HyperFrames grades a clip or an overlap seen at one sample only as info, a
// flicker; the samples are a scene's in, key and out, so one sample is a frame
// the viewer holds, and the gate counts it. The caption band is the same text
// against the bottom 220 px.
const ONCE_COUNTED = new Set([
  "clipped_text",
  "text_box_overflow",
  "content_overlap",
]);
const layout = collect();
const band = collect();
for (const f of checked.layout.findings)
  if (
    f.severity === "error" ||
    (f.occurrences === 1 && ONCE_COUNTED.has(f.code))
  )
    layout.add(
      f.time,
      sceneOf(f),
      `${f.code}${f.text ? `: ${quote(f.text)}` : ""}`,
    );
for (const p of plan)
  for (const t of p.samples)
    for (const e of textsAt(t).filter(readable)) {
      const { left, top, right, bottom } = e.rect;
      if (
        left < MARGIN_X ||
        top < MARGIN_Y ||
        right > WIDTH - MARGIN_X ||
        bottom > HEIGHT - MARGIN_Y
      )
        layout.add(t, p.sc.id, `${quote(e.text)} is outside the safe margin`);
      if (e.fontPx < TEXT_PX)
        layout.add(
          t,
          p.sc.id,
          `${quote(e.text)} is ${Math.round(e.fontPx)} px, under ${TEXT_PX} px`,
        );
      if (bottom > BAND)
        band.add(
          t,
          p.sc.id,
          `${quote(e.text)} at y ${Math.round(top)}-${Math.round(bottom)}`,
        );
    }

// Contrast: HyperFrames grades a failure a warning, the gate fails on it.
const contrast = collect();
for (const f of checked.contrast.findings)
  if (f.code === "contrast_aa_failure")
    contrast.add(
      f.time,
      sceneOf(f),
      `${quote(f.text)} ${f.ratio}:1 under ${f.requiredRatio}:1`,
    );

// Reading time, scene by scene on the probe's frames.
const reading = plan.flatMap((p) =>
  readingFindings({
    id: p.sc.id,
    end: p.end,
    frames: frames
      .filter((f) => f.t >= p.sc.start - 1e-6 && f.t < p.end)
      .map((f) => ({ t: f.t, texts: sceneTexts(f) })),
    samples: p.samples,
  }),
);

// The runtime errors the browser reports while mounting the scenes. An at()
// naming a word the alignment lacks is an anchor; any other error a scene's
// script raises is a script error, which would otherwise render a static frame
// and pass every gate. `[HyperFrames] composition script error: <scene> <error>`
// names the scene.
const SCRIPT_ERROR = /^\[HyperFrames\] composition script error: (\S+)\s*/;
const anchors = [];
const scriptErrors = [];
const flagged = new Set();
const addOnce = (list, line) => list.includes(line) || list.push(line);
for (const f of checked.runtime.findings) {
  const anchor = f.message?.match(NO_WORD_RE);
  if (anchor) {
    const start = timeline.scenes.find((s) => s.id === anchor[2])?.start ?? 0;
    flagged.add(anchor[2]);
    addOnce(
      anchors,
      `${start.toFixed(2)} s ${anchor[2]}: ${NO_WORD} "${anchor[1]}"`,
    );
  } else if (f.severity === "error") {
    const named = f.message?.match(SCRIPT_ERROR);
    const what = (named ? f.message.slice(named[0].length) : f.message) ?? "";
    const scene = named?.[1] ?? sourceScene(f) ?? "project";
    flagged.add(scene);
    addOnce(
      scriptErrors,
      `${scene}: ${what.split("\n")[0].trim().slice(0, 120)}`,
    );
  }
}
// A scene registers its timeline last, so one missing means its script stopped.
// HyperFrames 0.8.206 reports no error for a throwing script that also names a
// second timeline, so the missing timeline is the evidence for an unnamed one.
for (const { sc } of plan)
  if (!events[sc.id] && !flagged.has(sc.id))
    scriptErrors.push(
      `${sc.id}: no timeline registered as window.__timelines["${sc.id}"], so its script stopped`,
    );

// Must and avoid, carried from explainer-video's script check: a whole-word
// match over each scene's voiced words and the readable text its samples show.
// The voiced words, not script.json, since the script can be edited after the
// voice was made.
const hasWord = (corpus, item) =>
  new RegExp(
    `(?<![\\p{L}\\p{N}])${item.toLowerCase().replace(/[.*+?^$|()[\]{}\\]/g, "\\$&")}(?![\\p{L}\\p{N}])`,
    "u",
  ).test(corpus);
const corpus = plan.map((p) => ({
  id: p.sc.id,
  text: [
    p.sc.words.map((w) => w.text).join(" "),
    ...p.samples.flatMap((t) =>
      textsAt(t)
        .filter(readable)
        .map((e) => e.text),
    ),
  ]
    .join("\n")
    .toLowerCase(),
}));
const coverage = [];
for (const m of brief?.must ?? [])
  if (!corpus.some((c) => hasWord(c.text, m)))
    coverage.push(`must "${m}" is not said or shown`);
for (const x of brief?.avoid ?? []) {
  const hit = corpus.filter((c) => hasWord(c.text, x));
  if (hit.length)
    coverage.push(`avoid "${x}" is in ${hit.map((c) => c.id).join(", ")}`);
}

// Chapter titles, in a video in chapters: each chapter's first frame, its opener
// scene's frame 0 (which the probe's grid holds), draws every word of the
// chapter's title, compared as must and avoid compare words.
const titles = (timeline.chapters ?? []).flatMap((ch) => {
  const drawn = textsAt(ceil3(ch.start))
    .filter(readable)
    .map((e) => e.text)
    .join("\n")
    .toLowerCase();
  const missing = (
    ch.title.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? []
  ).filter((w) => !hasWord(drawn, w));
  return missing.length
    ? [
        `${ch.start.toFixed(2)} s ${ch.scenes[0]}: chapter ${ch.n} ${quote(ch.title)} is not drawn on its first frame, missing ${[...new Set(missing)].join(", ")}`,
      ]
    : [];
});

// Sound only, in a video in chapters: a chapter renders without over.html (its
// sound plays in the one mix), so what it paints never reaches the video. The
// probe measures what paints at each frame; a wrapper that draws nothing passes.
const drawnByOver = timeline.chapters ? frames.flatMap((f) => f.over) : [];
const overDrawing = drawnByOver.length
  ? [
      `over.html draws ${[...new Set(drawnByOver)].join(", ")}: a chapter renders without it, so move the drawing into a scene file`,
    ]
  : [];

// Support: the claims check (source/claims.mjs) passed on the narration and the
// source pack as they stand, so every sentence stating a fact cites excerpts
// that support it, and that narration is the one voiced, so the render speaks
// only judged words.
const pack = maybeJson(run, "excerpts.json");
const claims = maybeJson(run, "claims.json");
const unvoiced = script.scenes
  .filter(
    (s, i) =>
      voiced.scenes[i]?.words.map((w) => w.text).join(" ") !==
      s.narration.join(" "),
  )
  .map(
    (s) =>
      `scene ${s.id}'s narration is not what voice.json voiced: run the voice stage again`,
  );
if (voiced.scenes.length !== script.scenes.length)
  unvoiced.push(
    `voice.json voiced ${voiced.scenes.length} scene(s), the script holds ${script.scenes.length}: run the voice stage again`,
  );
const support = !pack
  ? ["no excerpts.json: run the source stage"]
  : !claims
    ? ["no claims.json: run source/claims.mjs"]
    : claims.passed !== claimsKey(script, pack)
      ? [
          "the claims check has not passed on this script and source pack: run source/claims.mjs",
        ]
      : unvoiced;

const summary = (ev) =>
  `${ev.length} finding(s)${ev.length ? `, first: ${ev[0]}` : ""}`;
const kit = soundKit(run);
const bed = await orFail(() => bedLevel({ proj, timeline, kit, backend }));
// Each gate's findings and floor, and what a pass measured where it says more
// than its count of findings.
const judged = {
  determinism: [determinism, "the same pixels twice"],
  layout: [layout.lines(), `none, text >= ${TEXT_PX} px, margin 5%`],
  contrast: [contrast.lines(), "WCAG AA 4.5:1, 3:1 large"],
  reading: [
    reading,
    "each text readable 0.8 s (up to 3 words) or 0.3 s a word, 1.2 s at least",
  ],
  "caption band": [band.lines(), "no readable text in the bottom 220 px"],
  anchors: [anchors, "every anchor names an aligned word"],
  "script errors": [scriptErrors, "every scene's script runs"],
  sounds: [
    soundFindings(plan, events),
    "every <audio> has an id and plays at its live data-start, in its scene",
  ],
  licence: [
    licenceFindings(
      events,
      fs.readFileSync(path.join(proj, "index.html"), "utf8"),
      kit,
    ),
    "every <audio> but the narration has a licence record in sound.json",
  ],
  "bed level": [bed.evidence, `${BED_LU} LU`, bed.measured],
  "must and avoid": [
    coverage,
    "every must said or shown, no avoid said or shown",
  ],
  ...(timeline.chapters && {
    "chapter titles": [
      titles,
      "each chapter's first frame draws every word of its title",
    ],
    "sound only": [overDrawing, "over.html holds <audio> and no drawn element"],
  }),
  support: [support, "the claims check passed on this script and source pack"],
};
const gates = Object.fromEntries(
  Object.entries(judged).map(([name, [evidence, floor, passed]]) => [
    name,
    {
      status: evidence.length ? "fail" : "pass",
      measured: (!evidence.length && passed) || summary(evidence),
      floor,
      evidence,
    },
  ]),
);

// The critic judges the first launch's stills; its rounds count per voice.
const { voice } = timeline;
const sameVoice = prev?.voice === voice;
gates.critic = criticGate({
  run,
  plan,
  stills: new Map(a.map(([t, pixels, file]) => [t, { pixels, path: file }])),
  script,
  pack,
  prev: sameVoice ? prev.gates.critic : null,
  fail,
});
const failing = Object.values(gates).filter((g) => g.status === "fail").length;
const pending = gates.critic.status === "pending";

const warned = warnings({
  plan,
  events,
  script,
  castVoices: voicedCast(voiced),
  sound: kit,
  total: timeline.total,
  proj,
});

// The fix cap: a red run on one voice is one fix attempt, the same inputs
// judged again are none, and a pass or a new voice starts the count again. The
// voice, not script.json: the gates judge the voiced words, so a script edited
// without voicing again changes nothing they judge. A critic still to judge is
// no pass, and the critic's red second round is final.
const attempts = gates.critic.final
  ? MAX_ATTEMPTS + 1
  : !failing
    ? pending && sameVoice
      ? (prev.attempts ?? 0)
      : 0
    : sameVoice && prev.inputs === inputs
      ? Math.max(prev.attempts ?? 0, 1)
      : (sameVoice ? (prev.attempts ?? 0) : 0) + 1;
fs.writeFileSync(
  path.join(run, "gates.json"),
  JSON.stringify(
    { inputs, voice, attempts, gates, warnings: warned },
    null,
    2,
  ) + "\n",
);

for (const [name, g] of Object.entries(gates)) {
  console.log(
    `gate ${name}: ${g.status}: ${g.measured}${g.status === "pending" ? "" : ` vs ${g.floor}`}`,
  );
  for (const e of g.evidence.slice(1)) console.log(`  ${e}`);
}
for (const w of warned) console.log(`warn ${w}`);
console.log(
  `gates: ${Object.keys(gates).length - failing - pending} pass, ${failing} fail${
    pending ? ", 1 pending" : ""
  }${
    gates.critic.final
      ? "; stop: the critic's second round is red, no video"
      : failing
        ? attempts > MAX_ATTEMPTS
          ? "; stop: red after two fix attempts, no video"
          : `; next: fix attempt ${attempts} of ${MAX_ATTEMPTS}`
        : pending
          ? `; next: run the critic, round ${gates.critic.rounds.length + 1} of 2`
          : ""
  }`,
);
process.exit(failing || pending ? 1 : 0);
