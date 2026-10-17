// The video gates through their process doors: a run rendered with the canned
// backend, whose marker words (fake-backend.mjs) break one gate each, and the
// gates stage run on its own against what the render left.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  findChrome,
  sheetFrames,
} from "../../skills/explainer-video/scripts/lib/backend.mjs";
import {
  sceneFrames,
  stripStart,
} from "../../skills/explainer-video/scripts/lib/motion.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import {
  catalogue,
  dest,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";
import { CLEAN, critique, judged } from "./critic.mjs";
import { ARABIC, SCRIPT } from "./scene-file.mjs";

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
  return { tmp, dir, env, dirs, log: env.EXPLAINER_VIDEO_FAKE_LOG };
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
    /^gates: 5 pass, 1 fail, 1 pending; next: fix attempt 1 of 2$/m,
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
  assert.match(r.out, /^gates: 7 pass, 0 fail$/m);
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
    "gate determinism: pass: 0 of 3 scene(s) differ between two renders vs none, the same pixels twice",
    "gate critic: pass: 0 hard failure(s), mean scores clarity 4.0, legibility 5.0, fit 4.0, motion 3.0, round 1 of 2 vs no unreadable or invented content; scores advise",
    "gates: 7 pass, 0 fail",
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
    "determinism",
    "critic",
  ]);
  assert.deepEqual(gates.gates.determinism, {
    status: "pass",
    measured: "0 of 3 scene(s) differ between two renders",
    floor: "none, the same pixels twice",
    attempts: 0,
    evidence: [],
  });
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
  const r = renderUnjudged(fx, SCRIPT);
  assert.match(r.out, /^gates: 6 pass, 0 fail, 1 pending/m, r.out + r.err);
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

// The fixture's script voices about 15 s, under any length brief.mjs takes,
// so a score test's brief asks for a quarter minute to pass the voice stage.
function quarterMinute(fx) {
  const file = path.join(fx.dir, "brief.json");
  fs.writeFileSync(
    file,
    JSON.stringify({ ...JSON.parse(read(file)), length: 0.25 }, null, 2),
  );
}

// The brief set to score=ace-step; `installed` stamps the ace-step row as
// setup leaves it.
function aceBrief(fx, installed = true) {
  const b = spawnSync(
    process.execPath,
    [
      path.join(skill, "scripts", "brief", "brief.mjs"),
      fx.dir,
      "voice=am_fenrir",
      "score=ace-step",
    ],
    { env: fx.env, encoding: "utf8" },
  );
  assert.equal(b.status, 0, b.stderr);
  quarterMinute(fx);
  const d = dest(
    catalogue().find((r) => r.id === "ace-step"),
    fx.dirs,
  );
  if (installed) {
    fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(d, ".stamp"), "");
  }
  return d;
}

test("a brief with score=ace-step mixes ACE-Step's music under the narration on the device the card allows, once per seed", () => {
  const fx = fixture();
  const dir = aceBrief(fx);
  const env = { EXPLAINER_VIDEO_FAKE_GPU: "7.5" };
  const r = render(fx, undefined, env);
  assert.equal(r.code, 0, r.out + r.err);
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  const [a] = calls(fx, "aceStep");
  const s = JSON.parse(read(fx.dir, "score.json"));
  assert.deepEqual(
    { ...a, caption: typeof a.caption },
    {
      call: "aceStep",
      dir,
      device: "cpu",
      seconds: timeline.total,
      seed: s.seed,
      caption: "string",
    },
  );
  assert.equal(s.score, "ace-step");
  assert.equal(s.device, "cpu");
  assert.equal(s.preset, undefined);
  const [m] = calls(fx, "master");
  assert.equal(wav(m.bed).seconds, Math.round(timeline.total * 48000) / 48000);
  assert.equal(stage(fx, "render/render.mjs", env).code, 0);
  assert.equal(
    calls(fx, "aceStep").length,
    1,
    "the same seed made the music again",
  );
  assert.equal(calls(fx, "master")[1].bed, m.bed);
});

test("an ACE-Step run that fails stops render with its reason", () => {
  const fx = fixture();
  aceBrief(fx);
  const r = render(fx, undefined, { EXPLAINER_VIDEO_FAKE_ACE_EXIT: "1" });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^render: ace-step exited 1$/m);
  assert.deepEqual(calls(fx, "master"), []);
});

test("a brief with score=ace-step before setup installed it says to run setup", () => {
  const fx = fixture();
  aceBrief(fx, false);
  const r = render(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^render: ace-step is not installed: run \/explainer-video setup, asking for ace-step$/m,
  );
  assert.deepEqual(calls(fx, "aceStep"), []);
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
  quarterMinute(fx);
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

test("an Arabic render passes the right to left checks, and each broken reading rule fails layout", () => {
  const fx = fixture(ARABIC);
  fx.env.GEMINI_API_KEY = "test-key";
  const green = render(fx);
  assert.equal(green.code, 0, green.out + green.err);
  const index = path.join(fx.dir, "composition", "index.html");
  const good = read(index);
  for (const [broken, why] of [
    [
      good.replace('<html lang="ar">', '<html lang="ar" dir="rtl">'),
      "dir on the page root html",
    ],
    [good.replaceAll(' dir="rtl"', ""), 'Arabic reads ltr "'],
    [
      good.replace("40px/1.7", "40px/1.3"),
      'line height 1.3 under the ink 1.35 of ibm-plex-sans-arabic "',
    ],
    [
      good.replace(" white-space: nowrap;", ""),
      'Latin run wraps "pull request"',
    ],
    [
      good.replace(
        " white-space: nowrap;",
        " white-space: nowrap; unicode-bidi: normal;",
      ),
      'Latin run not isolated "pull request"',
    ],
    [
      good.replaceAll('<bdi class="lat">pull request</bdi>', "pull request"),
      'Latin run not isolated in "',
    ],
  ]) {
    fs.writeFileSync(index, broken);
    fs.rmSync(path.join(fx.dir, ".cache", "gates"), { recursive: true });
    const r = stage(fx, "gates/gates.mjs");
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.out, /^gate layout: fail: /m);
    assert.ok(
      record(fx).gates.layout.evidence.some((e) => e.includes(why)),
      `${why}: ${record(fx).gates.layout.evidence.join(" | ")}`,
    );
  }
  fs.writeFileSync(index, good);
  fs.rmSync(path.join(fx.dir, ".cache", "gates"), { recursive: true });
  const fixed = stage(fx, "gates/gates.mjs");
  assert.equal(fixed.code, 0, fixed.out + fixed.err);
});

test("an English run quoting an Arabic word is not held to the right to left reading rules", () => {
  const fx = fixture();
  const r = render(fx, SCRIPT.replace('"value": "code"', '"value": "كود"'));
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^gate layout: pass: /m);
});

test("Arabic text in a code frame, which reads left to right as written, passes the reading checks", () => {
  const fx = fixture(ARABIC.replace("\\ngh pr create", '\\necho \\"تم\\"'));
  fx.env.GEMINI_API_KEY = "test-key";
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^gate layout: pass: /m);
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
    /^gates: 5 pass, 1 fail, 1 pending; next: fix attempt 2 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 2);
  const third = render(
    fx,
    clipped.replace('"value": "code"', '"value": "more code"'),
  );
  assert.equal(third.code, 1);
  assert.match(
    third.out,
    /^gates: 5 pass, 1 fail, 1 pending; stop: red after two fix attempts, no video$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 3);
  const renarrated = render(
    fx,
    clipped.replace("Here is how.", "Here is why."),
  );
  assert.match(
    renarrated.out,
    /^gates: 5 pass, 1 fail, 1 pending; next: fix attempt 1 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 1);
});

test("a red that moves from layout to contrast and back still stops", () => {
  const fx = fixture();
  assertRed(fx, render(fx, titled("clipped")), "layout", "clipped");
  const second = render(fx, titled("dim"));
  assert.match(
    second.out,
    /^gates: 5 pass, 1 fail, 1 pending; next: fix attempt 2 of 2$/m,
  );
  assert.equal(record(fx).gates.layout.attempts, 0);
  assert.equal(record(fx).gates.contrast.attempts, 1);
  const third = render(fx, titled("clipped"));
  assert.equal(third.code, 1);
  assert.match(
    third.out,
    /^gates: 5 pass, 1 fail, 1 pending; stop: red after two fix attempts, no video$/m,
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
    /^gates: 5 pass, 1 fail, 1 pending; next: fix attempt 1 of 2$/m,
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
function renderUnjudged(fx, text, extra) {
  fs.writeFileSync(path.join(fx.dir, "script.md"), text);
  for (const s of ["script/compile.mjs", "voice/voice.mjs"])
    assert.equal(stage(fx, s).code, 0, s);
  return stage(fx, "render/render.mjs", extra);
}

test("a render the critic has not judged is held: critic pending, a contact sheet per scene cut from the MP4, no HyperFrames snapshot, no attempt", () => {
  const fx = fixture();
  const r = renderUnjudged(fx, SCRIPT);
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
    /^gates: 6 pass, 0 fail, 1 pending; next: run the critic, round 1 of 2$/m,
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
  renderUnjudged(
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
          scores: { clarity: 3, legibility: 5, fit: 2, motion: 3 },
          worst: [],
        }
      : CLEAN,
  );
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^gate critic: fail: 1 hard failure\(s\), first: [\d.]+ s steps: invented: the card "ten times faster" .* vs /m,
  );
  assert.match(r.out, /^gates: 6 pass, 1 fail; next: fix attempt 1 of 2$/m);
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
  assert.ok(!fs.existsSync(delivered(fx)));
  assert.equal(record(fx).gates.critic.attempts, 1);
  assert.equal(record(fx).attempts, 1);
  assert.match(read(fx.dir, "gates.md"), /^## critic$/m);
  assertGreen(fx, render(fx, SCRIPT));
});

test("low scores with no hard failure pass the critic, the scores in the gates report", () => {
  const fx = fixture();
  renderUnjudged(fx, SCRIPT);
  const steps = JSON.parse(read(fx.dir, "timeline.json")).scenes[1];
  critique(fx.dir, (id) => ({
    failures: [],
    scores: { clarity: 1, legibility: 2, fit: 1, motion: 2 },
    note: "The card says little.",
    worst:
      id === "steps"
        ? [
            {
              at: steps.start + 1,
              what: "The card appears all at once.",
              evidence: "strip frames 4-7",
              fix: "Stagger the reveal.",
            },
          ]
        : [],
  }));
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    r.out,
    /^gate critic: pass: 0 hard failure\(s\), mean scores clarity 1\.0, legibility 2\.0, fit 1\.0, motion 2\.0, round 1 of 2 vs /m,
  );
  const md = read(fx.dir, "gates.md");
  assert.match(md, /^## Critic scores$/m);
  assert.match(
    md,
    /^\| steps \| 1 \| 2 \| 1 \| 2 \| The card says little\. \|$/m,
  );
  assert.match(md, /^### Worst defects$/m);
  assert.match(
    md,
    new RegExp(
      `^- steps at ${steps.start + 1} s: The card appears all at once\\. \\(strip frames 4-7\\)\\. Fix: Stagger the reveal\\.$`,
      "m",
    ),
  );
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
  const r3 = renderUnjudged(fx, SCRIPT);
  assert.equal(r3.code, 0, r3.out + r3.err);
  assert.match(
    r3.out,
    /^gate critic: pass: .*round 2 of 2, carried: no third round vs /m,
  );
  assert.equal(calls(fx, "sheet").length, 6, "no sheets for the third render");
  assert.equal(record(fx).gates.critic.rounds.length, 2);
  // Verdicts that appear for the third render add no third round.
  const g = record(fx);
  assert.ok(!g.gates.critic.rounds.includes(g.gates.critic.key));
  const third = path.join(fx.dir, ".cache", "critic", g.gates.critic.key);
  fs.mkdirSync(third, { recursive: true });
  for (const f of fs.readdirSync(path.join(fx.dir, g.gates.critic.sheets)))
    if (f.endsWith(".png"))
      fs.writeFileSync(
        path.join(third, f.replace(/\.png$/, ".json")),
        JSON.stringify({
          ...CLEAN,
          failures: [{ kind: "invented", what: "x" }],
        }),
      );
  const r3b = stage(fx, "render/render.mjs");
  assert.equal(r3b.code, 0, r3b.out + r3b.err);
  assert.match(r3b.out, /^gate critic: pass: .*carried: no third round vs /m);
  assert.equal(record(fx).gates.critic.rounds.length, 2);
  // New narration is a new script: its critic starts at round 1.
  const r4 = renderUnjudged(fx, SCRIPT.replace("Here is how.", "Here is why."));
  assert.match(r4.out, /^gate critic: pending: round 1 of 2, /m);
});

test("a malformed verdict stops the gates, naming the scene and what is wrong", () => {
  const fx = fixture();
  renderUnjudged(fx, SCRIPT);
  critique(fx.dir);
  const hook = path.join(fx.dir, record(fx).gates.critic.sheets, "hook.json");
  const scores = CLEAN.scores;
  // The hook scene runs from 0 s; a worst entry inside it, then one thing wrong.
  const worst = (n, o = {}) =>
    Array(n).fill({
      at: 0.5,
      what: "The title snaps in.",
      evidence: "strip frames 4-7",
      fix: "Ease the title in.",
      ...o,
    });
  const unmoved = { ...scores, motion: undefined };
  for (const [verdict, why] of [
    ["{", /JSON/],
    [{ scores, worst: [] }, /no failures list/],
    [
      { failures: [{ kind: "ugly", what: "x" }], scores, worst: [] },
      /failure 1 kind "ugly" is not unreadable or invented/,
    ],
    [
      { failures: [{ kind: "invented", what: " " }], scores, worst: [] },
      /failure 1 says nothing/,
    ],
    [
      { failures: [], scores: { ...scores, fit: 4.5 }, worst: [] },
      /score fit is not a whole number 1 to 5/,
    ],
    [
      { failures: [], scores: unmoved, worst: [] },
      /score motion is not a whole number 1 to 5/,
    ],
    [{ failures: [], scores }, /no worst list/],
    [
      { failures: [], scores, worst: worst(4) },
      /worst holds 4 entries, at most 3/,
    ],
    [
      { failures: [], scores, worst: worst(1, { at: 999 }) },
      /worst 1 at 999 is not a time inside the scene/,
    ],
    [{ failures: [], scores, worst: [null] }, /worst 1 is not an object/],
    [
      { failures: [], scores, worst: worst(1, { at: "0.5" }) },
      /worst 1 at 0.5 is not a time inside the scene/,
    ],
    [
      { failures: [], scores, worst: worst(1, { fix: " " }) },
      /worst 1 has no fix/,
    ],
  ]) {
    fs.writeFileSync(
      hook,
      typeof verdict === "string" ? verdict : JSON.stringify(verdict),
    );
    const r = stage(fx, "render/render.mjs");
    assert.equal(r.code, 1, r.out + r.err);
    const line = r.err.match(/^gates: critic verdict hook\.json: (.*)$/m);
    assert.ok(line, r.err);
    assert.match(line[1], why);
  }
});

test("a contact sheet shows the scene's quarter marks and its own last frame, even for a scene starting between frames", () => {
  assert.deepEqual(sheetFrames({ start: 2, duration: 4, fps: 30 }), [
    60,
    [90, 120, 150, 179],
  ]);
  // 28.25 s to 45.9 s at 30 fps: frames 848 to 1376; 1377 is the next scene's.
  assert.deepEqual(sheetFrames({ start: 28.25, duration: 17.65, fps: 30 }), [
    848,
    [980, 1112, 1244, 1376],
  ]);
});

test("a hard failure in the critic's second round stops the run: no third round could judge a fix", () => {
  const fx = fixture();
  const invented = () => ({
    ...CLEAN,
    failures: [{ kind: "invented", what: "a figure no sentence states" }],
  });
  renderUnjudged(fx, SCRIPT);
  critique(fx.dir, invented);
  const r1 = stage(fx, "render/render.mjs");
  assert.match(r1.out, /^gates: 6 pass, 1 fail; next: fix attempt 1 of 2$/m);
  renderUnjudged(fx, SCRIPT.replace('"value": "code"', '"value": "the code"'));
  critique(fx.dir, invented);
  const r2 = stage(fx, "render/render.mjs");
  assert.equal(r2.code, 1, r2.out + r2.err);
  assert.match(r2.out, /^gate critic: fail: .*round 2 of 2 vs /m);
  assert.match(
    r2.out,
    /^gates: 6 pass, 1 fail; stop: the critic's second round is red, no video$/m,
  );
  assert.ok(record(fx).attempts >= 3, "the storyboard reads it as stopped");
});

test("a verdict stands only for the evidence it read: new cites or a changed cited excerpt is judged again", () => {
  const fx = fixture();
  const excerpts = (text) =>
    fs.writeFileSync(
      path.join(fx.dir, "excerpts.json"),
      JSON.stringify({ excerpts: [{ id: "ex-1", text }] }),
    );
  excerpts("Ship reads the issue first.");
  assert.equal(render(fx).code, 0);
  excerpts("Ship reads the issue and its comments.");
  const r1 = stage(fx, "render/render.mjs");
  assert.equal(r1.code, 1, r1.out + r1.err);
  assert.match(r1.out, /^gate critic: pending: round 2 of 2, /m);
  const fresh = fixture();
  assert.equal(render(fresh).code, 0);
  const r2 = renderUnjudged(
    fresh,
    SCRIPT.replace("It reads the issue. [ex-1]", "It reads the issue. [ex-2]"),
  );
  assert.equal(r2.code, 1, r2.out + r2.err);
  assert.match(r2.out, /^gate critic: pending: round 2 of 2, /m);
});

// The fake backend's peak for a moving scene: its largest difference sits at
// entry n/3, which is frame first + n/3 + 1.
const peakOf = (s) => {
  const { first, n } = sceneFrames({
    start: s.start,
    duration: s.duration,
    fps: 30,
  });
  return { first, n, frame: first + Math.floor(n / 3) + 1 };
};

test("determinism renders each scene's peak-motion frame twice in two browsers and compares decoded pixels, not files", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  const frames = calls(fx, "frame");
  assert.equal(frames.length, 6, "two renders of one frame per scene");
  timeline.scenes.forEach((s, i) => {
    const [a, b] = frames.slice(2 * i, 2 * i + 2);
    assert.equal(a.t, +(peakOf(s).frame / 30).toFixed(3));
    assert.equal(b.t, a.t);
    assert.notEqual(a.out, b.out);
    // The files differ in metadata on every render; the pixels do not.
    assert.notEqual(read(a.out), read(b.out));
    assert.ok(a.out.includes(path.join(".cache", "gates", "frames")), a.out);
  });
  assert.equal(calls(fx, "bandMotion").length, 3);
});

test("a second gates run on an unchanged render makes no frame render call", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const before = [calls(fx, "frame").length, calls(fx, "bandMotion").length];
  const r = stage(fx, "gates/gates.mjs");
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^gate determinism: pass: /m);
  assert.deepEqual(
    [calls(fx, "frame").length, calls(fx, "bandMotion").length],
    before,
  );
});

test("a frame that renders differently twice fails determinism, names the scene and frame time, and stops with no fix attempt", () => {
  const fx = fixture();
  const r = renderUnjudged(
    fx,
    SCRIPT.replace('"value": "code"', '"value": "flaky code"'),
  );
  assert.equal(r.code, 1, r.out + r.err);
  const steps = JSON.parse(read(fx.dir, "timeline.json")).scenes[1];
  const { frame } = peakOf(steps);
  assert.match(
    r.out,
    new RegExp(
      `^gate determinism: fail: 1 of 3 scene\\(s\\) differ between two renders, first: ${steps.start.toFixed(2)} s steps: frame ${frame} \\(${(frame / 30).toFixed(2)} s\\) renders differently twice, sha256 [0-9a-f]{12} vs [0-9a-f]{12}: `,
      "m",
    ),
  );
  assert.match(
    r.out,
    /^gates: \d pass, 1 fail, 1 pending; stop: determinism is red, a skill defect to report, no fix attempt, no video$/m,
  );
  assert.ok(!/next: fix attempt/.test(r.out), r.out);
  const g = record(fx);
  assert.ok(g.attempts >= 3, "the storyboard reads it as stopped");
  assert.equal(g.gates.determinism.status, "fail");
  assert.equal(g.gates.determinism.evidence.length, 1);
  // Both renders' files are the evidence.
  for (const f of g.gates.determinism.evidence[0].match(/\.cache\/\S+\.png/g))
    assert.ok(fs.existsSync(path.join(fx.dir, f)), f);
  assert.match(read(fx.dir, "gates.md"), /^## determinism$/m);
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
  assert.ok(!fs.existsSync(delivered(fx)));
});

test("each moving scene gets a motion strip and record beside its contact sheet; a still scene gets a record that says so and no strip", () => {
  const first = fixture();
  assert.equal(renderUnjudged(first, SCRIPT).code, 1);
  const timeline = JSON.parse(read(first.dir, "timeline.json"));
  const starts = timeline.scenes.map((s) => s.start);
  // The same script times the same in a second fixture, whose middle scene is still.
  const fx = fixture();
  const r = renderUnjudged(fx, SCRIPT, {
    EXPLAINER_VIDEO_FAKE_STILL: JSON.stringify([starts[1]]),
  });
  assert.equal(r.code, 1, r.out + r.err);
  const dir = path.join(fx.dir, record(fx).gates.critic.sheets);
  timeline.scenes.forEach((s, i) => {
    assert.ok(fs.existsSync(path.join(dir, `${s.id}.png`)));
    const rec = JSON.parse(read(dir, `${s.id}.motion.json`));
    if (i === 1) {
      assert.ok(!fs.existsSync(path.join(dir, `${s.id}.motion.png`)));
      assert.equal(rec.still, true);
      assert.equal(rec.peak, null);
      assert.equal(rec.strip, null);
      // Nothing moves for the whole scene, a dead beat from end to end.
      assert.equal(rec.stills.length, 1);
      return;
    }
    const { first: f, n, frame } = peakOf(s);
    const from = stripStart(frame, f, n);
    assert.ok(fs.existsSync(path.join(dir, `${s.id}.motion.png`)));
    assert.deepEqual(rec, {
      still: false,
      peak: { frame, t: +(frame / 30).toFixed(3) },
      strip: {
        first: +(from / 30).toFixed(3),
        last: +((from + 11) / 30).toFixed(3),
      },
      stills: [],
    });
    const cut = calls(fx, "strip").find((c) =>
      c.output.endsWith(`${s.id}.motion.png`),
    );
    assert.equal(cut.first, from);
  });
  assert.equal(calls(fx, "strip").length, 2);
  // Cut only when absent: gating again cuts nothing.
  stage(fx, "render/render.mjs");
  assert.equal(calls(fx, "strip").length, 2);
  assert.equal(calls(fx, "sheet").length, 3);
});

test("verdicts cached in the old format are judged again, not refused by the new validator", () => {
  const fx = fixture();
  assert.equal(renderUnjudged(fx, SCRIPT).code, 1);
  const g = record(fx);
  const script = JSON.parse(read(fx.dir, "script.json"));
  // The key the code before the verdict format change computed.
  const old = crypto
    .createHash("sha256")
    .update(g.render)
    .update(
      JSON.stringify([
        script.title,
        script.scenes.map((s) =>
          s.cites.map((ids) => ids.map((id) => [id, undefined])),
        ),
      ]),
    )
    .digest("hex")
    .slice(0, 16);
  assert.notEqual(old, g.gates.critic.key);
  const dir = path.join(fx.dir, ".cache", "critic", old);
  fs.mkdirSync(dir, { recursive: true });
  for (const s of script.scenes)
    fs.writeFileSync(
      path.join(dir, `${s.id}.json`),
      JSON.stringify({
        failures: [],
        scores: { clarity: 4, legibility: 5, fit: 4 },
      }),
    );
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.ok(!/critic verdict/.test(r.err), r.err);
  assert.match(
    r.out,
    /^gate critic: pending: round 1 of 2, 0 of 3 scene\(s\) judged, /m,
  );
});

test("two old-format rounds recorded in gates.json are dropped, not read by the new validator", () => {
  const fx = fixture();
  assert.equal(renderUnjudged(fx, SCRIPT).code, 1);
  const g = record(fx);
  const script = JSON.parse(read(fx.dir, "script.json"));
  // A record from before the format: two rounds, no format field.
  const rounds = ["a".repeat(16), "b".repeat(16)];
  delete g.gates.critic.format;
  g.gates.critic.rounds = rounds;
  fs.writeFileSync(path.join(fx.dir, "gates.json"), JSON.stringify(g));
  const dir = path.join(fx.dir, ".cache", "critic", rounds[1]);
  fs.mkdirSync(dir, { recursive: true });
  for (const s of script.scenes)
    fs.writeFileSync(
      path.join(dir, `${s.id}.json`),
      JSON.stringify({
        failures: [],
        scores: { clarity: 4, legibility: 5, fit: 4 },
      }),
    );
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.ok(!/critic verdict/.test(r.err), r.err);
  assert.match(
    r.out,
    /^gate critic: pending: round 1 of 2, 0 of 3 scene\(s\) judged, /m,
  );
  assert.equal(record(fx).gates.critic.format, 2);
});
