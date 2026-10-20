// The gates stage: the run's last render judged against the skill's floors.
//
//   node gates.mjs <run-folder>
//
// Reads <run>/script.json, timeline.json, style.json (its floors through
// lib/style.mjs), score.json, composition/ and out/<slug>.mp4|.srt. Samples
// each scene every 15 frames from its start, at its settled last frame and at
// each timeline event, one sample per whole frame; HyperFrames' check and the
// layout probe measure the samples of every scene not cached in
// <run>/.cache/gates/, judged here for layout and contrast.
// Loudness, captions and the sound effects per minute are measured on every
// run. The critic gate reads the verdicts the critic subagents wrote beside
// this render's contact sheets, in <run>/.cache/critic/<key>/ (the render and
// the cites it read), cutting a sheet per scene first when a verdict is
// missing. Deletes nothing: the render stage acts on the verdict.
// stdout: `gate <name>: pass|fail: <measured> vs <floor>` for layout, contrast,
//         loudness, captions, sfx, determinism and critic (or `gate critic:
//         pending: ...`), then `gates: <n> pass, <m> fail[, 1 pending]`, when
//         red ending `; next: fix attempt <a> of 2` or `; stop: red after two
//         fix attempts, no video` (`; stop: determinism is red, a skill defect
//         to report, no fix attempt, no video` when determinism is red), when
//         only pending `; next: run the critic, round <r> of 2`
// writes: <run>/gates.json, gates.md, .cache/gates/ (with the frames each
//         determinism check rendered), .cache/critic/
// exit:   0 every gate passes · 1 a gate fails or is pending, or `gates: <why>`
//         on stderr · 2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { scriptHash, stopped } from "../lib/gatestop.mjs";
import { judge } from "../lib/layout.mjs";
import { sampleTimes } from "../lib/motion.mjs";
import { LUFS, floors, grammar, loadStyle, typeRoles } from "../lib/style.mjs";
import { hyperframesEnv, loadBackend, renderInputs } from "../lib/tools.mjs";
import { FPS, H, W, contentBox } from "../render/compose.mjs";
import { captionFindings, cuesOf } from "./captions.mjs";
import { sceneEvents } from "./events.mjs";
import { fullestFrame, motionAndDeterminism } from "./scene.mjs";
import { cutSheets, readPrevKeys } from "./sheets.mjs";
import { SCORES, KINDS, checkVerdict } from "./verdict.mjs";

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
    fail(e.message);
  }
}
const slug = path.basename(path.resolve(run));
const r3 = (n) => +n.toFixed(3);
const hash = (...parts) => {
  const h = crypto.createHash("sha256");
  for (const p of parts)
    h.update(
      typeof p === "string" || Buffer.isBuffer(p) ? p : JSON.stringify(p),
    );
  return h.digest("hex").slice(0, 16);
};
const read = (f) => fs.readFileSync(path.join(run, f), "utf8");
const mp4 = `out/${slug}.mp4`;
const srtFile = `out/${slug}.srt`;
for (const f of [
  "script.json",
  "timeline.json",
  "style.json",
  "composition/index.html",
  "score.json",
  mp4,
  srtFile,
])
  if (!fs.existsSync(path.join(run, f)))
    fail(`no ${f}: run the render stage first`);
const script = JSON.parse(read("script.json"));
const timeline = JSON.parse(read("timeline.json"));
let profile, floor;
try {
  profile = loadStyle(run, script.style);
  floor = floors(profile);
} catch (e) {
  fail(e.message);
}
const { textPx, margin } = floor.layout;
const backend = await loadBackend();

const cues = cuesOf(read("composition/index.html"));

// Per scene: its samples, and its layout and contrast evidence, cached by
// everything that draws its frames, every floor that judges them, and the
// code that draws, measures and judges: the root page's composer, this file,
// the probe, the contrast maths and the reading rules.
const inputs = renderInputs(
  [...new Set(typeRoles(script.language).map((r) => profile.type[r].font))],
  profile,
);
const source = [
  "../render/compose.mjs",
  "gates.mjs",
  "captions.mjs",
  "events.mjs",
  "scene.mjs",
  "sheets.mjs",
  "verdict.mjs",
  "../lib/backend.mjs",
  "../lib/backend/common.mjs",
  "../lib/backend/browser.mjs",
  "../lib/backend/media.mjs",
  "../lib/backend/voice.mjs",
  "../lib/backend/source.mjs",
  "../lib/layout.mjs",
  "../lib/motion.mjs",
  "../lib/terms.mjs",
  "../lib/style.mjs",
].map((f) =>
  fs.readFileSync(fileURLToPath(new URL(f, import.meta.url)), "utf8"),
);
const cacheDir = path.join(run, ".cache", "gates");
fs.mkdirSync(cacheDir, { recursive: true });
const env = hyperframesEnv();
const comp = path.join(run, "composition");
const {
  moves,
  seams,
  times: eventTimes,
  moving,
} = sceneEvents(
  await orFail(() => backend.events(comp, { env })),
  timeline.scenes,
);
const plan = timeline.scenes.map((sc) => {
  const end = sc.start + sc.duration;
  const times = sampleTimes({ ...sc, fps: FPS, events: eventTimes });
  const file = path.join(
    cacheDir,
    `${hash(
      read(`composition/scenes/${sc.id}.html`),
      [times, moves[sc.id], seams, W, H, sc.duration, sc.sentences],
      profile,
      script.title,
      inputs,
      // Cue starts are 3-place values, so the scene's bounds are too.
      cues.filter((c) => c.start >= r3(sc.start) && c.start < r3(end)),
      floor,
      source,
    )}.json`,
  );
  const cached = fs.existsSync(file)
    ? JSON.parse(fs.readFileSync(file, "utf8"))
    : null;
  return { sc, end, times, file, found: cached };
});

const todo = plan.filter((p) => !p.found);
if (todo.length) {
  const times = todo.flatMap((p) => p.times);
  const checked = await orFail(() => backend.check(comp, times, { env }));
  // A check that never reached the browser answers {ok: false, error} alone.
  if (!checked.layout || !checked.contrast)
    fail(
      `hyperframes check: ${checked.error ?? "no layout or contrast result"}`,
    );
  const frames = await orFail(() => backend.probe(comp, times, { env }));
  // A scene with no text of its own in any sample is a probe that saw nothing,
  // not a pass: captions and the header draw over every scene.
  for (const p of todo)
    if (
      !frames.some(
        (f) =>
          p.times.includes(f.t) && f.elements.some((e) => e.scene === p.sc.id),
      )
    )
      fail(`layout probe: no text in scene ${p.sc.id}`);
  for (const p of todo) p.found = { layout: [], contrast: [] };
  // One defect held across a scene is one finding: its first time, and the
  // number of samples it showed in.
  const seen = new Map();
  const add = (gate, t, what) => {
    const p = todo.find((p) => t < p.end - 1e-6) ?? todo.at(-1);
    const key = `${gate} ${p.sc.id}: ${what}`;
    const hit = seen.get(key);
    if (hit) return (hit.n += 1);
    seen.set(key, { p, gate, at: p.found[gate].length, t, what, n: 1 });
    p.found[gate].push("");
  };
  const settle = () => {
    for (const { p, gate, at, t, what, n } of seen.values())
      p.found[gate][at] =
        `${t.toFixed(2)} s ${p.sc.id}: ${what}${n > 1 ? ` (${n} samples)` : ""}`;
  };
  judge(checked, frames, floor, add, moving);
  settle();
  for (const p of todo) {
    p.found.fullest = fullestFrame(p, frames, moving);
    await motionAndDeterminism(p, {
      run,
      mp4,
      comp,
      env,
      backend,
      orFail,
      seams,
      band: contentBox(grammar(profile).layout),
    });
  }
  for (const p of todo) fs.writeFileSync(p.file, JSON.stringify(p.found));
}

// Loudness, on the encoded MP4.
const { lufs, peak } = await orFail(() =>
  backend.loudness(path.join(run, mp4)),
);
const { tolerance, peak: ceiling } = floor.loudness;
const loud = [];
if (Math.abs(lufs - LUFS) > tolerance)
  loud.push(
    `integrated ${lufs.toFixed(1)} LUFS is ${Math.abs(lufs - LUFS).toFixed(1)} LU off ${LUFS}`,
  );
if (peak > ceiling)
  loud.push(`true peak ${peak.toFixed(1)} dBTP over ${ceiling}`);

// Captions: the timeline's words, the composition's cues, and the SRT as the
// cues' copy.
const caps = captionFindings({ timeline, cues, srtText: read(srtFile) });

// Sound effects: the most cues the score puts in any minute.
const sfxCues = JSON.parse(read("score.json")).cues;
const { perMinute } = floor.sfx;
let busiest = { n: 0, t: 0 };
for (const c of sfxCues) {
  const n = sfxCues.filter((o) => o.t >= c.t && o.t < c.t + 60).length;
  if (n > busiest.n) busiest = { n, t: c.t };
}
const sfx =
  busiest.n > perMinute
    ? [
        `${busiest.n} cues in the minute from ${busiest.t.toFixed(2)} s, over ${perMinute}`,
      ]
    : [];

// The verdicts. A gate's attempts count its consecutive red renders of this
// script, and the run's attempts every red render of it since the last green
// one, so a red that moves between gates still stops: a pass, or a changed
// script, starts a count again, and the same render judged again is no new
// attempt.
const summary = (ev, noun = "finding(s)") =>
  `${ev.length} ${noun}${ev.length ? `, first: ${ev[0]}` : ""}`;
const layoutFindings = plan.flatMap((p) => p.found.layout);
const contrastFindings = plan.flatMap((p) => p.found.contrast);
// Led by the scene's start, as layout's lines are, with both renders' files.
const differing = plan
  .filter((p) => p.found.determinism.a !== p.found.determinism.b)
  .map((p) => {
    const d = p.found.determinism;
    return `${p.sc.start.toFixed(2)} s ${p.sc.id}: frame ${d.frame} (${d.t.toFixed(2)} s) renders differently twice, sha256 ${d.a.slice(0, 12)} vs ${d.b.slice(0, 12)}: ${d.files.join(", ")}`;
  });
const judged = {
  layout: [
    layoutFindings,
    summary(layoutFindings),
    `none, text >= ${textPx} px, margin ${r3(margin * 100)}%`,
  ],
  contrast: [
    contrastFindings,
    summary(contrastFindings),
    `body ${floor.contrast.body}:1, large ${floor.contrast.large}:1`,
  ],
  loudness: [
    loud,
    `${lufs.toFixed(1)} LUFS, peak ${peak.toFixed(1)} dBTP`,
    `${LUFS} +-${tolerance} LUFS, peak <= ${ceiling} dBTP`,
  ],
  captions: [caps, `${cues.length} cue(s), ${summary(caps)}`, "none"],
  sfx: [
    sfx,
    `${sfxCues.length} cue(s), at most ${busiest.n} in a minute`,
    `<= ${perMinute} a minute`,
  ],
  determinism: [
    differing,
    summary(differing, `of ${plan.length} scene(s) differ between two renders`),
    "none, the same pixels twice",
  ],
};
const scriptKey = scriptHash(script);
const renderHash = hash(
  read("composition/index.html"),
  ...fs
    .readdirSync(path.join(run, "composition", "scenes"))
    .filter((f) => f.endsWith(".html"))
    .sort()
    .map((f) => read(`composition/scenes/${f}`)),
  fs.readFileSync(path.join(run, mp4)),
  read(srtFile),
);
const recordFile = path.join(run, "gates.json");
const prev = fs.existsSync(recordFile)
  ? JSON.parse(fs.readFileSync(recordFile, "utf8"))
  : null;
const same = prev?.script === scriptKey;
const again = same && prev.render === renderHash;
const count = (failing, before) =>
  !failing ? 0 : again ? before || 1 : before + 1;

// The critic: Claude subagents each judge one scene's contact sheet, cut from
// the MP4 by ffmpeg (never HyperFrames' snapshot, which sends frames to
// Gemini), and write <scene>.json beside it. A hard failure blocks; scores
// advise. Two rounds of one script at most: once two renders are judged, a
// later one carries the second round's verdict rather than ask for a third.
// Beside each contact sheet it cuts a motion strip and a motion record.
// Bumped when the verdict's format or what its sheet shows changes, so a
// verdict cached in the old one is judged again rather than refused by the new
// validator or kept for a sheet the critic no longer reads.
const CRITIC_FORMAT = 3;
// A verdict stands for the render, for what else the critic read (the title,
// each sentence's cites and the cited excerpts' text) and for its format.
const excerptsFile = path.join(run, "excerpts.json");
const excerptText = new Map(
  fs.existsSync(excerptsFile)
    ? JSON.parse(fs.readFileSync(excerptsFile, "utf8")).excerpts.map((x) => [
        x.id,
        x.text,
      ])
    : [],
);
// Every critic reads every excerpt the script cites, so a scene's key below
// takes all of them, not its own cites alone.
const criticRead = [
  script.title,
  script.scenes.map((s) =>
    s.cites.map((ids) => ids.map((id) => [id, excerptText.get(id)])),
  ),
];
const criticKey = hash(renderHash, criticRead, CRITIC_FORMAT);
const sheetsOf = (h) => path.posix.join(".cache", "critic", h);
const verdicts = (h) =>
  timeline.scenes.map((sc) => {
    const f = path.join(run, sheetsOf(h), `${sc.id}.json`);
    if (!fs.existsSync(f)) return null;
    const bad = (why) => fail(`critic verdict ${sc.id}.json: ${why}`);
    let v;
    try {
      v = JSON.parse(fs.readFileSync(f, "utf8"));
    } catch (e) {
      bad(e.message);
    }
    checkVerdict(v, sc, bad);
    return { ...v, id: sc.id, start: sc.start };
  });
// Rounds judged in another verdict format are not carried: their verdicts would
// meet the validator, which refuses them, and are judged again instead.
const keptRounds = same && prev.gates.critic?.format === CRITIC_FORMAT;
const rounds = keptRounds ? (prev.gates.critic.rounds ?? []) : [];
const criticAttempts = keptRounds ? (prev.gates.critic.attempts ?? 0) : 0;
const dir = sheetsOf(criticKey);
// Past two rounds a render carries the second round's verdict: no sheets.
if (rounds.includes(criticKey) || rounds.length < 2) {
  fs.mkdirSync(path.join(run, dir), { recursive: true });
  // The previous render's verdict under the same scene key is carried, so only
  // changed scenes are pending.
  const prevSheets = keptRounds ? prev.gates.critic.sheets : null;
  const prevKeys =
    !prevSheets || prevSheets === dir
      ? {}
      : readPrevKeys(run, prevSheets, fail);
  const keys = await cutSheets({
    run,
    mp4,
    dir,
    plan,
    backend,
    orFail,
    script,
    criticRead,
    hash,
    format: CRITIC_FORMAT,
    prevSheets,
    prevKeys,
  });
  fs.writeFileSync(path.join(run, dir, "keys.json"), JSON.stringify(keys));
}
let judgedBy;
const own = verdicts(criticKey);
if (own.every(Boolean) && (rounds.includes(criticKey) || rounds.length < 2)) {
  if (!rounds.includes(criticKey)) rounds.push(criticKey);
  judgedBy = { vs: own, round: rounds.indexOf(criticKey) + 1 };
} else if (rounds.length >= 2) {
  const vs = verdicts(rounds[1]);
  if (vs.every(Boolean)) judgedBy = { vs, round: 2, carried: true };
}
const wantCritic = `no ${KINDS.join(" or ")} content; scores advise`;
let critic;
if (judgedBy) {
  const { vs, round, carried } = judgedBy;
  // Led by the scene's start, as layout's lines are, so the storyboard's gate
  // stop reopens the scene's card.
  const evidence = vs.flatMap((v) =>
    v.failures.map(
      (x) => `${v.start.toFixed(2)} s ${v.id}: ${x.kind}: ${x.what}`,
    ),
  );
  const mean = (k) =>
    (vs.reduce((n, v) => n + v.scores[k], 0) / vs.length).toFixed(1);
  critic = {
    status: evidence.length ? "fail" : "pass",
    measured: `${summary(evidence, "hard failure(s)")}, mean scores ${SCORES.map((k) => `${k} ${mean(k)}`).join(", ")}, round ${round} of 2${carried ? ", carried: no third round" : ""}`,
    floor: wantCritic,
    attempts: count(evidence.length, criticAttempts),
    evidence,
    sheets: sheetsOf(carried ? rounds[1] : criticKey),
    rounds,
    format: CRITIC_FORMAT,
    scores: vs.map((v) => ({
      scene: v.id,
      ...Object.fromEntries(SCORES.map((k) => [k, v.scores[k]])),
      note: v.note ?? "",
      worst: v.worst,
    })),
  };
} else {
  critic = {
    status: "pending",
    measured: `round ${rounds.length + 1} of 2, ${own.filter(Boolean).length} of ${own.length} scene(s) judged, contact sheets in ${dir}`,
    floor: wantCritic,
    attempts: criticAttempts,
    evidence: [],
    sheets: dir,
    rounds,
    format: CRITIC_FORMAT,
  };
}

const gates = {};
for (const [name, [evidence, measured, wanted]] of Object.entries(judged))
  gates[name] = {
    status: evidence.length ? "fail" : "pass",
    measured,
    floor: wanted,
    attempts: count(
      evidence.length,
      same ? (prev.gates[name]?.attempts ?? 0) : 0,
    ),
    evidence,
  };
gates.critic = { ...critic, key: criticKey };
const red = Object.entries(gates).filter(([, g]) => g.status === "fail");
const pending = critic.status === "pending";
// A hard failure in the critic's last round is final: no third round can
// judge a fix, so the run stops now rather than spend an attempt it cannot win.
const criticFinal = critic.status === "fail" && judgedBy.round === 2;
// A red determinism gate stops at once as well: the same script rendered twice
// differs, so no fix to the script could clear it.
const nondeterministic = gates.determinism.status === "fail";
const attempts = Math.max(
  count(red.length, same ? prev.attempts : 0),
  criticFinal || nondeterministic ? 3 : 0,
);
fs.writeFileSync(
  recordFile,
  JSON.stringify(
    { script: scriptKey, render: renderHash, attempts, gates },
    null,
    2,
  ) + "\n",
);

const cell = (s) => String(s).replaceAll("|", "\\|");
fs.writeFileSync(
  path.join(run, "gates.md"),
  [
    "# Video gates",
    "",
    "| gate | status | measured | floor | attempts |",
    "| --- | --- | --- | --- | --- |",
    ...Object.entries(gates).map(
      ([n, g]) =>
        `| ${n} | ${g.status} | ${cell(g.measured)} | ${cell(g.floor)} | ${g.attempts} |`,
    ),
    ...red.flatMap(([n, g]) => [
      "",
      `## ${n}`,
      "",
      ...g.evidence.map((e) => `- ${e}`),
    ]),
    ...(critic.scores
      ? [
          "",
          "## Critic scores",
          "",
          `| scene | ${SCORES.join(" | ")} | note |`,
          `| --- | ${SCORES.map(() => "---").join(" | ")} | --- |`,
          ...critic.scores.map(
            (s) =>
              `| ${s.scene} | ${SCORES.map((k) => s[k]).join(" | ")} | ${cell(s.note)} |`,
          ),
          ...(critic.scores.some((s) => s.worst.length)
            ? [
                "",
                "### Worst defects",
                "",
                ...critic.scores.flatMap((s) =>
                  s.worst.map(
                    (w) =>
                      `- ${s.scene} at ${w.at} s: ${w.what} (${w.evidence}). Fix: ${w.fix}`,
                  ),
                ),
              ]
            : []),
        ]
      : []),
  ].join("\n") + "\n",
);
for (const [name, g] of Object.entries(gates))
  console.log(`gate ${name}: ${g.status}: ${g.measured} vs ${g.floor}`);
console.log(
  `gates: ${Object.keys(gates).length - red.length - pending} pass, ${red.length} fail${pending ? ", 1 pending" : ""}${
    red.length
      ? nondeterministic
        ? "; stop: determinism is red, a skill defect to report, no fix attempt, no video"
        : criticFinal
          ? "; stop: the critic's second round is red, no video"
          : stopped(attempts)
            ? "; stop: red after two fix attempts, no video"
            : `; next: fix attempt ${attempts} of 2`
      : pending
        ? `; next: run the critic, round ${rounds.length + 1} of 2`
        : ""
  }`,
);
process.exit(red.length || pending ? 1 : 0);
