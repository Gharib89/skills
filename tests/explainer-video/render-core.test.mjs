// The render stage through its process door, part 1: a run folder compiled and
// voiced with the canned backend, and assertions on the composition, captions,
// delivery, caches and manifest.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { judged } from "./critic.mjs";
import {
  dest,
  lockHash,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";
import { SCRIPT } from "./scene-file.mjs";
import {
  at,
  calls,
  comp,
  delivered,
  fixture,
  profile,
  put,
  read,
  render,
  seconds,
  skill,
  stage,
  unescape,
} from "./render-lib.mjs";

test("render composes every scene, renders with the CLI's guards, delivers and records the run", () => {
  const fx = fixture();
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);

  const hf = calls(fx);
  assert.equal(hf.length, 2);
  const chrome = dest({ kind: "chrome" }, fx.dirs);
  for (const c of hf) {
    assert.deepEqual(c.env, {
      HYPERFRAMES_NO_TELEMETRY: "1",
      DO_NOT_TRACK: "1",
      HYPERFRAMES_NO_UPDATE_CHECK: "1",
      HOME: chrome,
      USERPROFILE: chrome,
    });
    assert.ok(!c.args.includes("init") && !c.args.includes("snapshot"));
    assert.equal(c.args[0], "render");
    assert.ok(c.args.includes("--strict"), c.args.join(" "));
  }
  const video = hf.find((c) => !c.args.includes("png-sequence"));
  assert.deepEqual(video.hosts, ["hook", "steps", "gate"]);
  assert.equal(video.args[video.args.indexOf("--fps") + 1], "30");

  const index = comp(fx);
  assert.match(index, /<meta charset="UTF-8"/);
  assert.match(
    index,
    /data-composition-id="main"[^>]*data-width="1920" data-height="1080"/,
  );
  const srcs = [...index.matchAll(/data-composition-src="([^"]+)"/g)].map(
    (m) => m[1],
  );
  assert.deepEqual(srcs, [
    "scenes/hook.html",
    "scenes/steps.html",
    "scenes/gate.html",
  ]);
  for (const s of srcs) {
    const scene = comp(fx, s);
    assert.match(scene, /^<template/);
    assert.match(scene, /window\.__timelines\["(hook|steps|gate)"\]/);
  }
  assert.ok(!/https?:|\.\.\//.test(index), "no CDN or parent paths");
  assert.match(index, /<script src="gsap\.min\.js"><\/script>/);
  assert.equal(comp(fx, "gsap.min.js"), "/* gsap */");
  assert.deepEqual(
    fs.readdirSync(path.join(fx.dir, "composition", "fonts")).sort(),
    [
      "inter-latin-400-normal.woff2",
      "inter-latin-600-normal.woff2",
      "jetbrains-mono-latin-400-normal.woff2",
      "source-serif-4-latin-600-normal.woff2",
    ],
  );
  assert.match(
    index,
    /@font-face \{ font-family: "inter"; src: url\("fonts\/inter-latin-600-normal\.woff2"\); font-weight: 600;/,
  );
  assert.match(index, /--accent: #cc6c54;/);
  assert.match(index, /\.cue \{[^}]*font: 400 40px\/1\.3 "inter"/);
  assert.match(
    index,
    /<audio id="narration" src="narration\.wav" data-start="0"/,
  );
  assert.ok(fs.existsSync(path.join(fx.dir, "composition", "narration.wav")));

  const ignore = read(fx.tmp, "proj", "explainers", ".gitignore").split("\n");
  for (const e of [
    "*/composition/",
    "*/out/",
    "*/.cache/",
    "*/script.json",
    "*/timeline.json",
  ])
    assert.ok(ignore.includes(e), e);

  // The SRT carries the composition's cues, text and times alike.
  const cues = [
    ...index.matchAll(
      /<div class="cue clip" data-start="([\d.]+)" data-duration="([\d.]+)"[^>]*>(.*?)<\/div>/g,
    ),
  ].map((m) => ({ start: +m[1], end: +m[1] + +m[2], text: unescape(m[3]) }));
  const srt = read(fx.dir, "out", "demo.srt")
    .trim()
    .split(/\n\n/)
    .map((b) => {
      const [n, times, ...text] = b.split("\n");
      const [a, z] = times.split(" --> ");
      return {
        n: +n,
        start: seconds(a),
        end: seconds(z),
        text: text.join(" "),
      };
    });
  assert.equal(srt.length, cues.length);
  assert.ok(cues.length >= 7, `${cues.length} cues`);
  srt.forEach((s, i) => {
    assert.equal(s.n, i + 1);
    assert.equal(s.text, cues[i].text);
    assert.ok(Math.abs(s.start - cues[i].start) < 0.002, `cue ${i + 1} start`);
    assert.ok(Math.abs(s.end - cues[i].end) < 0.002, `cue ${i + 1} end`);
    assert.ok(s.text.length <= 84, s.text);
    assert.ok(s.end > s.start);
  });
  assert.equal(srt[0].text, "Ship drives #626 to a merged pull request.");

  const timeline = JSON.parse(read(fx.dir, "timeline.json"));
  assert.deepEqual(
    timeline.scenes.map((s) => s.id),
    ["hook", "steps", "gate"],
  );
  assert.equal(timeline.scenes[1].start, timeline.scenes[0].duration);
  const last = timeline.scenes.at(-1);
  assert.ok(Math.abs(timeline.total - (last.start + last.duration)) < 0.002);
  const voiced = JSON.parse(read(fx.dir, "voice.json")).scenes.at(-1);
  // The hold, rounded up to a whole frame.
  const held = last.duration - (voiced.duration + 1);
  assert.ok(held > -0.002 && held < 1 / 30 + 0.002, "1 s hold");

  // Every scene is whole frames, written truncated so HyperFrames counts the
  // frames named, and the narration is that many frames of audio.
  let frames = 0;
  for (const s of timeline.scenes) {
    assert.equal(Math.ceil(s.start * 30), frames, `${s.id} start`);
    const n = Math.round(s.duration * 30);
    assert.ok(Math.abs(s.duration * 30 - n) < 0.001, `${s.id} duration`);
    assert.equal(Math.ceil(s.duration * 30), n, `${s.id} frames`);
    frames += n;
  }
  // A rate with a fractional sample count a frame rounds each scene to a
  // whole sample, so the total is within a sample a scene.
  const wav = fs.readFileSync(
    path.join(fx.dir, "composition", "narration.wav"),
  );
  const want = (frames * wav.readUInt32LE(24) * 2) / 30;
  assert.ok(
    Math.abs(wav.readUInt32LE(40) - want) <= timeline.scenes.length * 2,
    `narration is whole frames: ${wav.readUInt32LE(40)} bytes, want ${want}`,
  );

  for (const check of [
    "resolution",
    "frame rate",
    "aspect",
    "duration",
    "audio",
    "srt",
  ])
    assert.match(r.out, new RegExp(`^delivery ${check}: pass$`, "m"));
  const where = delivered(fx);
  assert.match(r.out, new RegExp(`^delivered: ${where}$`, "m"));
  assert.deepEqual(fs.readdirSync(where).sort(), [
    "demo.mp4",
    "demo.srt",
    "poster.png",
  ]);
  assert.equal(read(where, "poster.png"), "still of hook");
  assert.equal(read(fx.dir, "out", "poster.png"), "still of hook");
  // The render the critic held drew the stills and the video; the one after
  // reused both.
  assert.match(r.held.out, /^gates: 6 pass, 0 fail, 1 pending; next: /m);
  assert.deepEqual(
    calls(fx)
      .map((c) => (c.args.includes("png-sequence") ? "stills" : "video"))
      .sort(),
    ["stills", "video"],
  );
  assert.match(
    r.out.trim().split("\n").at(-1),
    /^render: demo\.mp4 \d+\.\d\d s, 3 scene\(s\), stills 3\/3 cached, video cached$/,
  );

  const manifest = JSON.parse(read(fx.dir, "manifest.json"));
  const version = read(skill, "SKILL.md").match(/^ {2}version: (\S+)$/m)[1];
  assert.deepEqual(manifest, {
    board: null,
    skill: version,
    lock: lockHash,
    profile: "claude-code",
    narrator: "am_fenrir",
    delivered: where,
  });
});

test("a second render with nothing changed calls HyperFrames no more; one changed visual re-renders only its still and the video", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  const first = calls(fx).length;
  const again = render(fx);
  assert.equal(again.code, 0, again.out + again.err);
  assert.equal(calls(fx).length, first);
  assert.match(again.out, /stills 3\/3 cached, video cached$/m);

  fs.writeFileSync(
    path.join(fx.dir, "script.md"),
    SCRIPT.replace('"value": "code"', '"value": "the code"'),
  );
  const changed = render(fx);
  assert.equal(changed.code, 0, changed.out + changed.err);
  assert.ok(changed.held, "the changed video goes to the critic again");
  const fresh = calls(fx).slice(first);
  assert.equal(fresh.length, 2);
  assert.deepEqual(fresh.find((c) => c.args.includes("png-sequence")).hosts, [
    "steps",
  ]);
  assert.match(changed.out, /stills 3\/3 cached, video cached$/m);
});

test("a delivery check that fails names the measure, exits 1 and copies nothing", () => {
  const fx = fixture();
  const r = render(fx, { EXPLAINER_VIDEO_FAKE_PROBE: '{"fps":25}' });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.out, /^delivery frame rate: fail: 25 vs 30$/m);
  assert.match(r.out, /^delivery resolution: pass$/m);
  assert.ok(!fs.existsSync(path.join(fx.tmp, "videos")));
  assert.ok(!fs.existsSync(path.join(fx.dir, "out", "demo.mp4")));
  // The failed video is not cached: the next run renders it again.
  const before = calls(fx).length;
  const again = judged(fx.dir, () => stage(fx, "render/render.mjs"));
  assert.equal(again.code, 0, again.out + again.err);
  assert.equal(calls(fx).length, before + 1);
  assert.match(again.out, /video rendered$/m);
});

test("a project with a separate git dir delivers under its own folder's name", () => {
  const fx = fixture();
  const git = spawnSync(
    "git",
    [
      ...["init", "-q", "--separate-git-dir", path.join(fx.tmp, "gd")],
      path.join(fx.tmp, "proj"),
    ],
    { env: fx.env },
  );
  assert.equal(git.status, 0);
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.ok(fs.existsSync(path.join(delivered(fx), "demo.mp4")));
});

test("a video a second longer than the timeline fails the duration check", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  fs.rmSync(path.join(fx.tmp, "videos"), { recursive: true });
  const total = JSON.parse(read(fx.dir, "timeline.json")).total;
  const r = render(fx, {
    EXPLAINER_VIDEO_FAKE_PROBE: JSON.stringify({ duration: total + 1 }),
  });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^delivery duration: fail: [\d.]+ s vs [\d.]+ s within 0\.25 s$/m,
  );
  assert.ok(!fs.existsSync(path.join(fx.tmp, "videos")));
  // The earlier render's MP4 and poster go too, not left beside a new SRT.
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
});

test("a narrator change after voicing asks for the voice stage again", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  put(
    fx.dir,
    "script.md",
    SCRIPT.replace("narrator: am_fenrir", "narrator: bf_emma"),
  );
  assert.equal(stage(fx, "script/compile.mjs").code, 0);
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^render: voice\.json holds narrator am_fenrir, the script asks for bf_emma: run the voice stage again/m,
  );
});

test("render before the voice stage says which stage to run", () => {
  const fx = fixture();
  assert.equal(stage(fx, "script/compile.mjs").code, 0);
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1);
  assert.match(r.err, /^render: no voice\.json: run the voice stage first/m);
});

test("render on a mistyped run folder says which stage to run and writes nothing", () => {
  const fx = fixture();
  const r = stage(
    { ...fx, dir: path.join(fx.tmp, "typo") },
    "render/render.mjs",
  );
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^render: no script\.json: run the compile stage first/m);
  assert.ok(!fs.existsSync(path.join(fx.tmp, ".gitignore")));
  assert.ok(!fs.existsSync(path.join(fx.tmp, "typo")));
});

test("the video encodes on NVENC where one works, the stills never ask for it, and a render is not reused across encode modes", () => {
  const fx = fixture();
  const nvenc = { EXPLAINER_VIDEO_FAKE_NVENC: "1" };
  const gpu = render(fx, nvenc);
  assert.equal(gpu.code, 0, gpu.out + gpu.err);
  const drawn = calls(fx);
  assert.deepEqual(
    drawn.map((c) => [
      c.args.includes("png-sequence"),
      c.args.includes("--gpu"),
    ]),
    [
      [true, false],
      [false, true],
    ],
  );

  const before = calls(fx).length;
  const cpu = render(fx);
  assert.equal(cpu.code, 0, cpu.out + cpu.err);
  const fresh = calls(fx).slice(before);
  assert.equal(fresh.length, 1);
  assert.ok(!fresh[0].args.includes("--gpu"));

  assert.match(render(fx, nvenc).out, /video cached$/m);
  assert.match(render(fx).out, /video cached$/m);
});
