// The video gates through their process doors: a run rendered with the canned
// backend, whose marker words (fake-backend.mjs) break one gate each, and the
// gates stage run on its own against what the render left.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { findChrome } from "../../skills/explainer-video/scripts/lib/backend.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";
import { CLEAN, critique, judged } from "./critic.mjs";
import { SCRIPT } from "./scene-file.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const skill = path.join(here, "..", "..", "skills", "explainer-video");

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// A temp machine as render.test.mjs lays it out.
function fixture(text = SCRIPT) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-gates-"));
  temps.push(tmp);
  const env = {
    PATH: process.env.PATH,
    HOME: path.join(tmp, "home"),
    XDG_CONFIG_HOME: path.join(tmp, "config"),
    XDG_DATA_HOME: path.join(tmp, "data"),
    XDG_CACHE_HOME: path.join(tmp, "cache"),
    XDG_VIDEOS_DIR: path.join(tmp, "videos"),
    EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
    EXPLAINER_VIDEO_FAKE_LOG: path.join(tmp, "calls.jsonl"),
  };
  const dirs = userDirs({ platform: "linux", env, home: env.HOME });
  for (const r of catalogue().filter((r) =>
    ["npm", "chrome", "font"].includes(r.kind),
  )) {
    const d = dest(r, dirs);
    fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(d, ".stamp"), "");
    for (const f of r.files ?? [])
      fs.writeFileSync(path.join(d, `${f}.woff2`), "woff2");
  }
  const gsap = path.join(dest({ kind: "npm" }, dirs), "node_modules", "gsap");
  fs.mkdirSync(path.join(gsap, "dist"), { recursive: true });
  fs.writeFileSync(path.join(gsap, "dist", "gsap.min.js"), "/* gsap */");
  const dir = path.join(tmp, "proj", "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "script.md"), text);
  return { tmp, dir, env, log: env.EXPLAINER_VIDEO_FAKE_LOG };
}

function stage(fx, script, extra = {}) {
  const r = spawnSync(
    process.execPath,
    [path.join(skill, "scripts", script), fx.dir],
    { env: { ...fx.env, ...extra }, encoding: "utf8" },
  );
  return { code: r.status, out: r.stdout, err: r.stderr };
}

// The script written, compiled and voiced, then rendered, a clean critic round
// taken when the critic alone holds the render.
function render(fx, text, extra) {
  if (text) fs.writeFileSync(path.join(fx.dir, "script.md"), text);
  for (const s of ["script/compile.mjs", "voice/voice.mjs"]) {
    const r = stage(fx, s);
    assert.equal(r.code, 0, `${s}: ${r.out}${r.err}`);
  }
  return judged(fx.dir, () => stage(fx, "render/render.mjs", extra));
}

const calls = (fx, name) =>
  fs.existsSync(fx.log)
    ? fs
        .readFileSync(fx.log, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
        .filter((c) => c.call === name)
    : [];
const read = (...p) => fs.readFileSync(path.join(...p), "utf8");
const record = (fx) => JSON.parse(read(fx.dir, "gates.json"));
const delivered = (fx) =>
  path.join(fx.tmp, "videos", "explainer-video", "proj", "demo");
const titled = (word) =>
  SCRIPT.replace("Issue to pull request", `Issue to ${word} request`);

// A red render: the gate's line, exit 1, nothing delivered, out/ gone.
function assertRed(fx, r, gate, why) {
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.out, new RegExp(`^gate ${gate}: fail: .*${why}`, "m"));
  assert.match(
    r.out,
    /^gates: 4 pass, 1 fail, 1 pending; next: fix attempt 1 of 2$/m,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
  assert.ok(!fs.existsSync(delivered(fx)));
  assert.equal(record(fx).gates[gate].status, "fail");
  assert.equal(record(fx).gates[gate].attempts, 1);
  assert.equal(record(fx).attempts, 1);
}
// Green on the fix: every gate passes, attempts back to 0, the video delivered.
function assertGreen(fx, r) {
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^gates: 6 pass, 0 fail$/m);
  for (const g of Object.values(record(fx).gates)) assert.equal(g.attempts, 0);
  assert.equal(record(fx).attempts, 0);
  assert.ok(fs.existsSync(path.join(delivered(fx), "demo.mp4")));
}

test("a clean render passes all six gates, writes the record and the report, and delivers", () => {
  const fx = fixture();
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const lines = r.out.split("\n").filter((l) => /^gates?\b/.test(l));
  assert.deepEqual(lines, [
    "gate layout: pass: 0 finding(s) vs none, text >= 18 px, margin 5%",
    "gate contrast: pass: 0 finding(s) vs body 4.5:1, large 3:1",
    "gate loudness: pass: -14.0 LUFS, peak -1.6 dBTP vs -14 +-1 LUFS, peak <= -1 dBTP",
    lines[3],
    lines[4],
    "gate critic: pass: 0 hard failure(s), mean scores clarity 4.0, legibility 5.0, fit 4.0, round 1 of 2 vs no unreadable or invented content; scores advise",
    "gates: 6 pass, 0 fail",
  ]);
  assert.match(
    lines[3],
    /^gate captions: pass: \d+ cue\(s\), 0 finding\(s\) vs none$/,
  );
  const sfx = JSON.parse(read(fx.dir, "score.json")).cues.length;
  assert.equal(
    lines[4],
    `gate sfx: pass: ${sfx} cue(s), at most ${sfx} in a minute vs <= 24 a minute`,
  );
  const gates = record(fx);
  assert.match(gates.script, /^[0-9a-f]{16}$/);
  assert.deepEqual(Object.keys(gates.gates), [
    "layout",
    "contrast",
    "loudness",
    "captions",
    "sfx",
    "critic",
  ]);
  assert.deepEqual(gates.gates.loudness, {
    status: "pass",
    measured: "-14.0 LUFS, peak -1.6 dBTP",
    floor: "-14 +-1 LUFS, peak <= -1 dBTP",
    attempts: 0,
    evidence: [],
  });
  const md = read(fx.dir, "gates.md");
  assert.match(md, /^# Video gates\n/);
  assert.match(md, /^\| gate \| status \| measured \| floor \| attempts \|$/m);
  assert.match(
    md,
    /^\| loudness \| pass \| -14\.0 LUFS, peak -1\.6 dBTP \| -14 \+-1 LUFS, peak <= -1 dBTP \| 0 \|$/m,
  );
  assert.ok(!/\d{4}-\d\d-\d\d/.test(md), "no date in the report");
  assert.ok(fs.existsSync(path.join(delivered(fx), "demo.mp4")));
  assert.match(r.out, /^delivered: /m);
  // Samples: every 15 frames from each scene's start, plus its settled last frame.
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  const want = timeline.scenes.flatMap((s) => {
    const last = s.start + s.duration - 1 / 30;
    const ts = [];
    for (let k = 0; s.start + k * 0.5 < last - 1e-6; k++)
      ts.push(+(s.start + k * 0.5).toFixed(3));
    return [...ts, +last.toFixed(3)];
  });
  assert.deepEqual(calls(fx, "probe")[0].times, want);
  assert.deepEqual(calls(fx, "check")[0].times, want);
});

test("the narration is mastered to -14 LUFS under the peak floor before the video renders", () => {
  const fx = fixture();
  rendered(fx, SCRIPT);
  const m = calls(fx, "master");
  assert.equal(m.length, 1);
  assert.equal(m[0].lufs, -14);
  assert.equal(m[0].peak, -1.5);
  assert.equal(path.basename(m[0].output), "narration.wav");
  assert.equal(path.basename(path.dirname(m[0].output)), "composition");
});

const wav = (f) => {
  const b = fs.readFileSync(f);
  return {
    channels: b.readUInt16LE(22),
    rate: b.readUInt32LE(24),
    bits: b.readUInt16LE(34),
    seconds: b.readUInt32LE(40) / b.readUInt32LE(28),
  };
};

test("by default a score of the whole timeline is mixed under the narration, its cues on the cuts", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const [m] = calls(fx, "master");
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  assert.deepEqual(wav(m.bed), {
    channels: 2,
    rate: 48000,
    bits: 24,
    seconds: Math.round(timeline.total * 48000) / 48000,
  });
  const s = JSON.parse(read(fx.dir, "score.json"));
  assert.equal(s.score, "on");
  assert.ok(s.preset && Number.isInteger(s.seed), JSON.stringify(s));
  const last = timeline.scenes.at(-1).words.at(-1);
  assert.deepEqual(s.cues, [
    ...timeline.scenes.slice(1).map((sc) => ({ type: "whoosh", t: sc.start })),
    { type: "sting", t: last.end },
  ]);
});

test("the same timings render the cached score again", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const first = calls(fx, "master")[0].bed;
  const before = fs.statSync(first).mtimeMs;
  assert.equal(stage(fx, "render/render.mjs").code, 0);
  const again = calls(fx, "master")[1].bed;
  assert.equal(again, first);
  assert.equal(fs.statSync(again).mtimeMs, before);
});

test("a brief with the score off masters the narration alone", () => {
  const fx = fixture();
  const b = spawnSync(
    process.execPath,
    [
      path.join(skill, "scripts", "brief", "brief.mjs"),
      fx.dir,
      "voice=am_fenrir",
      "score=off",
    ],
    { env: fx.env, encoding: "utf8" },
  );
  assert.equal(b.status, 0, b.stderr);
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(calls(fx, "master")[0].bed, undefined);
  assert.deepEqual(JSON.parse(read(fx.dir, "score.json")), {
    score: "off",
    cues: [],
  });
});

test("a clipped title fails layout, delivers nothing, and passes on the fix", () => {
  const fx = fixture();
  const r = render(fx, titled("clipped"));
  assertRed(fx, r, "layout", 'text_box_overflow "Issue to clipped request"');
  assert.match(
    r.out,
    /^gate layout: fail: \d+ finding\(s\), first: [\d.]+ s hook: /m,
  );
  assert.match(r.err, /^render: the gates did not pass: nothing delivered/m);
  const ev = record(fx).gates.layout.evidence;
  for (const kind of [
    "text_box_overflow",
    "overflow 4000x48 in 1600x48",
    "clipped",
  ]) {
    // A defect held across the scene is one line, counting its samples.
    const hits = ev.filter((e) => e.includes(`: ${kind}`));
    assert.equal(hits.length, 1, `${kind}: ${hits.join(" | ")}`);
    assert.match(hits[0], /\(\d+ samples\)$/);
  }
  assert.match(read(fx.dir, "gates.md"), /^## layout$/m);
  assertGreen(fx, render(fx, SCRIPT));
});

test("a tiny title fails layout as small text, and passes on the fix", () => {
  const fx = fixture();
  assertRed(
    fx,
    render(fx, titled("tiny")),
    "layout",
    'small 12 px "Issue to tiny request"',
  );
  assertGreen(fx, render(fx, SCRIPT));
});

test("a title in the margin fails layout as outside the safe margin, and passes on the fix", () => {
  const fx = fixture();
  assertRed(
    fx,
    render(fx, titled("edge")),
    "layout",
    'outside the safe margin "Issue to edge request"',
  );
  assertGreen(fx, render(fx, SCRIPT));
});

test("a title stacked on the kicker fails layout as an overlap, and passes on the fix", () => {
  const fx = fixture();
  assertRed(
    fx,
    render(fx, titled("stacked")),
    "layout",
    '"Ship" overlaps "Issue to stacked request"',
  );
  assertGreen(fx, render(fx, SCRIPT));
});

test("a contrast error from HyperFrames' check fails contrast", () => {
  const fx = fixture();
  const r = render(fx, SCRIPT, {
    EXPLAINER_VIDEO_FAKE_CHECK: JSON.stringify({
      ok: false,
      layout: { findings: [] },
      contrast: {
        findings: [
          {
            code: "low_contrast",
            severity: "error",
            time: 0,
            text: "x",
            ratio: 2.1,
            requiredRatio: 4.5,
          },
        ],
      },
    }),
  });
  assertRed(fx, r, "contrast", 'low_contrast "x" 2\\.1:1 under 4\\.5:1');
});

test("a dim title fails contrast on the frames, and passes on the fix", () => {
  const fx = fixture();
  assertRed(
    fx,
    render(fx, titled("dim")),
    "contrast",
    '"Issue to dim request" #c8c8c0 on #f5f4ed 1\\.\\d\\d:1 under 3:1',
  );
  assertGreen(fx, render(fx, SCRIPT));
});

test("small text in the accent is held to the body floor on the frames", () => {
  const fx = fixture();
  assertRed(
    fx,
    render(fx, titled("small")),
    "contrast",
    '"Issue to small request" #cc6c54 on #f5f4ed 3\\.26:1 under 4\\.5:1',
  );
  assertGreen(fx, render(fx, SCRIPT));
});

test("a hot mix fails loudness, and passes when the mix is fixed", () => {
  const fx = fixture();
  const r = render(fx, undefined, {
    EXPLAINER_VIDEO_FAKE_PROBE: '{"lufs":-9,"peak":0.4}',
  });
  assertRed(
    fx,
    r,
    "loudness",
    "-9\\.0 LUFS, peak 0\\.4 dBTP vs -14 \\+-1 LUFS",
  );
  assert.deepEqual(record(fx).gates.loudness.evidence, [
    "integrated -9.0 LUFS is 5.0 LU off -14",
    "true peak 0.4 dBTP over -1",
  ]);
  assertGreen(
    fx,
    judged(fx.dir, () => stage(fx, "render/render.mjs")),
  );
});

test("an SRT edited after a green render fails captions in the gates stage alone, which deletes nothing", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const srt = path.join(fx.dir, "out", "demo.srt");
  const good = read(srt);
  fs.writeFileSync(srt, good.replace("merged pull request", "merged request"));
  const r = stage(fx, "gates/gates.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^gate captions: fail: \d+ cue\(s\), 1 finding\(s\), first: SRT cue 1 reads "Ship drives #626 to a merged request\.", the composition "Ship drives #626 to a merged pull request\." vs none$/m,
  );
  assert.ok(fs.existsSync(srt));
  fs.writeFileSync(srt, good);
  const fixed = stage(fx, "gates/gates.mjs");
  assert.equal(fixed.code, 0, fixed.out + fixed.err);
  assert.equal(record(fx).gates.captions.attempts, 0);
});

test("a gate red three times in a row stops; a changed script starts the count again", () => {
  const fx = fixture();
  const clipped = titled("clipped");
  render(fx, clipped);
  // Each attempt changes the render: a card's value, the title still clipped.
  const second = render(
    fx,
    clipped.replace('"value": "code"', '"value": "the code"'),
  );
  assert.match(
    second.out,
    /^gates: 4 pass, 1 fail, 1 pending; next: fix attempt 2 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 2);
  const third = render(
    fx,
    clipped.replace('"value": "code"', '"value": "more code"'),
  );
  assert.equal(third.code, 1);
  assert.match(
    third.out,
    /^gates: 4 pass, 1 fail, 1 pending; stop: red after two fix attempts, no video$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 3);
  const renarrated = render(
    fx,
    clipped.replace("Here is how.", "Here is why."),
  );
  assert.match(
    renarrated.out,
    /^gates: 4 pass, 1 fail, 1 pending; next: fix attempt 1 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 1);
});

test("a red that moves from layout to contrast and back still stops", () => {
  const fx = fixture();
  assertRed(fx, render(fx, titled("clipped")), "layout", "clipped");
  const second = render(fx, titled("dim"));
  assert.match(
    second.out,
    /^gates: 4 pass, 1 fail, 1 pending; next: fix attempt 2 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 0);
  assert.equal(record(fx).gates.contrast.attempts, 1);
  const third = render(fx, titled("clipped"));
  assert.equal(third.code, 1);
  assert.match(
    third.out,
    /^gates: 4 pass, 1 fail, 1 pending; stop: red after two fix attempts, no video$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 1);
  assert.equal(record(fx).attempts, 3);
});

test("the same red render judged again keeps its attempt count", () => {
  const fx = fixture();
  render(fx, titled("clipped"));
  assert.match(record(fx).render, /^[0-9a-f]{16}$/);
  // out/ is emptied on red, so the render stage runs again on its cached video.
  const again = stage(fx, "render/render.mjs");
  assert.equal(again.code, 1, again.out + again.err);
  assert.match(
    again.out,
    /^gates: 4 pass, 1 fail, 1 pending; next: fix attempt 1 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 1);
});

test("a tightened floor is the floor applied and printed", () => {
  const fx = fixture();
  const p = JSON.parse(read(skill, "styles", "claude-code.json"));
  const styles = path.join(fx.tmp, "proj", "explainers", ".styles");
  fs.mkdirSync(styles, { recursive: true });
  fs.writeFileSync(
    path.join(styles, "big.json"),
    JSON.stringify({ ...p, gates: { layout: { textPx: 48 } } }),
  );
  const r = render(fx, SCRIPT.replace("style: claude-code", "style: big"));
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^gate layout: fail: \d+ finding\(s\), first: [\d.]+ s hook: small 40 px .* vs none, text >= 48 px, margin 5%$/m,
  );
});

test("a tightened sfx floor thins the score's cues to it", () => {
  const fx = fixture();
  const p = JSON.parse(read(skill, "styles", "claude-code.json"));
  const styles = path.join(fx.tmp, "proj", "explainers", ".styles");
  fs.mkdirSync(styles, { recursive: true });
  fs.writeFileSync(
    path.join(styles, "calm.json"),
    JSON.stringify({ ...p, gates: { sfx: { perMinute: 1 } } }),
  );
  const r = render(fx, SCRIPT.replace("style: claude-code", "style: calm"));
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    r.out,
    /^gate sfx: pass: 1 cue\(s\), at most 1 in a minute vs <= 1 a minute$/m,
  );
});

test("more sound effects in a minute than the floor fails sfx", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const cues = Array.from({ length: 25 }, (_, i) => ({ type: "whoosh", t: i }));
  fs.writeFileSync(
    path.join(fx.dir, "score.json"),
    JSON.stringify({ score: "on", cues }),
  );
  const r = stage(fx, "gates/gates.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^gate sfx: fail: 25 cue\(s\), at most 25 in a minute vs <= 24 a minute$/m,
  );
  assert.deepEqual(record(fx).gates.sfx.evidence, [
    "25 cues in the minute from 0.00 s, over 24",
  ]);
});

test("a second gates run with nothing changed calls neither check nor probe, yet measures loudness and captions", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const r = stage(fx, "gates/gates.mjs");
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(calls(fx, "check").length, 1);
  assert.equal(calls(fx, "probe").length, 1);
  // The render, its critic round's render again, and this run.
  assert.equal(calls(fx, "loudness").length, 3);
  assert.match(r.out, /^gate captions: pass: /m);
});

test("one changed scene re-gates only that scene's samples", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const r = render(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "the code"'),
  );
  assert.equal(r.code, 0, r.out + r.err);
  const [first, again] = calls(fx, "probe");
  const steps = JSON.parse(read(fx.dir, "timeline.json")).scenes[1];
  assert.ok(again.times.length > 1);
  assert.deepEqual(
    again.times,
    first.times.filter(
      (t) => t >= steps.start && t < steps.start + steps.duration,
    ),
  );
  assert.deepEqual(calls(fx, "check")[1].times, again.times);
});

test("the gates stage before a render says which stage to run", () => {
  const fx = fixture();
  assert.equal(stage(fx, "script/compile.mjs").code, 0);
  const r = stage(fx, "gates/gates.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^gates: no timeline\.json: run the render stage first$/m,
  );
  const usage = spawnSync(process.execPath, [
    path.join(skill, "scripts", "gates", "gates.mjs"),
  ]);
  assert.equal(usage.status, 2);
});

test("a probe that finds no text in a scene stops the gates as a tool error, not a pass", () => {
  const fx = fixture();
  const r = render(fx, SCRIPT, { EXPLAINER_VIDEO_FAKE_BLANK: "1" });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^gates: layout probe: no text in scene hook$/m);
  assert.match(r.err, /^render: the gates did not pass: nothing delivered$/m);
  assert.ok(!/^gate layout: pass/m.test(r.out), r.out);
  assert.ok(!fs.existsSync(path.join(fx.tmp, "videos")));
});

test("a scene drawing no text of its own stops the gates, though captions show over it", () => {
  const fx = fixture();
  const r = render(
    fx,
    SCRIPT.replace(
      '"props": { "kicker": "Ship", "title": "Issue to pull request", "subtitle": "One run, one merge" }',
      '"props": { "title": "" }',
    ),
  );
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^gates: layout probe: no text in scene hook$/m);
  assert.ok(!fs.existsSync(path.join(fx.tmp, "videos")));
});

test("findChrome finds Windows' chrome-headless-shell.exe", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-chrome-"));
  temps.push(home);
  const dir = path.join(
    home,
    ...[".cache", "hyperframes", "chrome", "win64-x"],
    "chrome-headless-shell-win64",
  );
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "chrome-headless-shell.exe"), "");
  assert.equal(findChrome(home), path.join(dir, "chrome-headless-shell.exe"));
});

test("a check that never reached the browser stops the gates as a tool error, not a pass", () => {
  const fx = fixture();
  const r = render(fx, SCRIPT, {
    EXPLAINER_VIDEO_FAKE_CHECK: '{"ok":false,"error":"Command failed"}',
  });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^gates: hyperframes check: Command failed$/m);
  assert.ok(!/^gate layout: pass/m.test(r.out), r.out);
  assert.ok(!fs.existsSync(path.join(fx.tmp, "videos")));
});

// The render stage alone, no critic round taken.
function rendered(fx, text) {
  fs.writeFileSync(path.join(fx.dir, "script.md"), text);
  for (const s of ["script/compile.mjs", "voice/voice.mjs"])
    assert.equal(stage(fx, s).code, 0, s);
  return stage(fx, "render/render.mjs");
}

test("a render the critic has not judged is held: critic pending, a contact sheet per scene cut from the MP4, no HyperFrames snapshot, no attempt", () => {
  const fx = fixture();
  const r = rendered(fx, SCRIPT);
  assert.equal(r.code, 1, r.out + r.err);
  const g = record(fx);
  assert.match(g.gates.critic.sheets, /^\.cache\/critic\/[0-9a-f]{16}$/);
  assert.ok(
    r.out.includes(
      `gate critic: pending: round 1 of 2, 0 of 3 scene(s) judged, contact sheets in ${g.gates.critic.sheets} vs no unreadable or invented content; scores advise\n`,
    ),
    r.out,
  );
  assert.match(
    r.out,
    /^gates: 5 pass, 0 fail, 1 pending; next: run the critic, round 1 of 2$/m,
  );
  assert.equal(g.attempts, 0);
  assert.equal(g.gates.critic.status, "pending");
  assert.ok(!fs.existsSync(delivered(fx)));
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  const sheets = calls(fx, "sheet");
  assert.deepEqual(
    sheets.map((c) => [path.basename(c.output), c.start, c.duration]),
    timeline.scenes.map((s) => [`${s.id}.png`, s.start, s.duration]),
  );
  for (const c of sheets) {
    assert.equal(path.basename(c.input), "demo.mp4");
    assert.ok(fs.existsSync(c.output), c.output);
  }
  for (const c of calls(fx, "hyperframes"))
    assert.ok(!c.args.includes("snapshot"), JSON.stringify(c.args));
  // The critic's round, then the render again on its cached video: delivered.
  assert.deepEqual(critique(fx.dir).sort(), ["gate", "hook", "steps"]);
  assertGreen(fx, stage(fx, "render/render.mjs"));
  assert.equal(calls(fx, "sheet").length, 3, "the sheets are cut once");
});

test("invented content on screen fails the critic, delivers nothing, and passes on the fix", () => {
  const fx = fixture();
  rendered(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "ten times faster"'),
  );
  critique(fx.dir, (id) =>
    id === "steps"
      ? {
          failures: [
            {
              kind: "invented",
              what: 'the card "ten times faster" is in no narration sentence or excerpt',
            },
          ],
          scores: { clarity: 3, legibility: 5, fit: 2 },
        }
      : CLEAN,
  );
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^gate critic: fail: 1 hard failure\(s\), first: [\d.]+ s steps: invented: the card "ten times faster" .* vs /m,
  );
  assert.match(r.out, /^gates: 5 pass, 1 fail; next: fix attempt 1 of 2$/m);
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
  assert.ok(!fs.existsSync(delivered(fx)));
  assert.equal(record(fx).gates.critic.attempts, 1);
  assert.equal(record(fx).attempts, 1);
  assert.match(read(fx.dir, "gates.md"), /^## critic$/m);
  assertGreen(fx, render(fx, SCRIPT));
});

test("low scores with no hard failure pass the critic, the scores in the gates report", () => {
  const fx = fixture();
  rendered(fx, SCRIPT);
  critique(fx.dir, () => ({
    failures: [],
    scores: { clarity: 1, legibility: 2, fit: 1 },
    note: "The card says little.",
  }));
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    r.out,
    /^gate critic: pass: 0 hard failure\(s\), mean scores clarity 1\.0, legibility 2\.0, fit 1\.0, round 1 of 2 vs /m,
  );
  const md = read(fx.dir, "gates.md");
  assert.match(md, /^## Critic scores$/m);
  assert.match(md, /^\| steps \| 1 \| 2 \| 1 \| The card says little\. \|$/m);
});

test("the critic judges two rounds of one script at most: a third render carries round two's verdict", () => {
  const fx = fixture();
  const r1 = render(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "the code"'),
  );
  assert.equal(r1.code, 0, r1.out + r1.err);
  const r2 = render(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "some code"'),
  );
  assert.match(r2.out, /^gate critic: pass: .*round 2 of 2 vs /m);
  const r3 = rendered(fx, SCRIPT);
  assert.equal(r3.code, 0, r3.out + r3.err);
  assert.match(
    r3.out,
    /^gate critic: pass: .*round 2 of 2, carried: no third round vs /m,
  );
  assert.equal(calls(fx, "sheet").length, 6, "no sheets for the third render");
  assert.equal(record(fx).gates.critic.rounds.length, 2);
  // New narration is a new script: its critic starts at round 1.
  const r4 = rendered(fx, SCRIPT.replace("Here is how.", "Here is why."));
  assert.match(r4.out, /^gate critic: pending: round 1 of 2, /m);
});

test("a malformed verdict stops the gates, naming the scene", () => {
  const fx = fixture();
  rendered(fx, SCRIPT);
  critique(fx.dir, (id) =>
    id === "hook"
      ? { failures: [{ kind: "ugly", what: "x" }], scores: CLEAN.scores }
      : CLEAN,
  );
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^gates: critic verdict hook\.json: failure 1 kind "ugly" is not unreadable or invented$/m,
  );
});
