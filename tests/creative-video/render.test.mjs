// The render stage (render/render.mjs) and the hf wrapper (hf.mjs): the
// project rendered through the canned HyperFrames, mastered, checked against
// the delivery contract and delivered into out/.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { SCENES } from "./voice-lib.mjs";
import {
  author,
  calls,
  exec,
  hf,
  project,
  read,
  readJson,
  render,
  timing,
  voiced,
} from "./timing-lib.mjs";

const ids = SCENES.map((s) => s.id);
const CHECKS = [
  "resolution",
  "frame rate",
  "aspect",
  "duration",
  "audio",
  "srt",
  "loudness",
  "true peak",
];

// A run folder timed and with every scene file authored.
function ready() {
  const fx = voiced();
  assert.equal(exec(timing, fx).code, 0);
  author(fx, ids);
  return fx;
}

test("a render delivers the mastered MP4, the SRT and the poster, with every delivery check printed as a pass", () => {
  const fx = ready();
  const r = exec(render, fx);
  assert.equal(r.code, 0, r.out + r.err);
  const tl = readJson(path.join(fx.dir, "timeline.json"));
  for (const c of CHECKS) assert.ok(r.out.includes(`delivery ${c}: pass\n`), c);
  assert.match(
    r.out,
    /^measured loudness: -14 LUFS integrated, -1\.6 dBTP true peak$/m,
  );
  assert.deepEqual(fs.readdirSync(path.join(fx.dir, "out")).sort(), [
    "demo.mp4",
    "demo.srt",
    "poster.png",
  ]);
  assert.ok(
    r.out.includes(`delivered: ${path.join(fx.dir, "out", "demo.mp4")}\n`),
  );
  assert.ok(
    r.out.includes(`render: demo.mp4 ${tl.total.toFixed(2)} s, 3 scene(s)\n`),
  );
  assert.equal(
    read(path.join(fx.dir, "out", "demo.srt")).match(/^\d+$/gm).length,
    tl.cues.length,
  );
  const manifest = readJson(path.join(fx.dir, "manifest.json"));
  assert.equal(manifest.narrator, "af_heart");
  assert.equal(manifest.lufs, -14);
  assert.equal(manifest.peak, -1.5);
  assert.match(manifest.lock, /^[0-9a-f]{16}$/);

  const log = calls(fx);
  const rendered = log.find((c) => c.call === "hyperframes");
  assert.deepEqual(rendered.args, [
    ...["render", "--strict", "--quiet", "--fps", "30", "--workers", "3"],
    ...["-o", path.join(fx.dir, ".cache", "render", "raw.mp4")],
  ]);
  assert.equal(rendered.cwd, project(fx));
  assert.equal(rendered.env.HYPERFRAMES_NO_TELEMETRY, "1");
  const norm = log.find((c) => c.call === "loudnorm");
  assert.equal(norm.input, path.join(fx.dir, ".cache", "render", "raw.mp4"));
  assert.equal(norm.output, path.join(fx.dir, "out", "demo.mp4"));
  assert.deepEqual([norm.lufs, norm.peak], [-14, -1.5]);
  const poster = log.find((c) => c.call === "poster");
  assert.equal(
    poster.seconds,
    +(tl.scenes[0].start + tl.scenes[0].duration / 2).toFixed(3),
  );
});

test("a true peak over -1.0 dBTP fails its check, empties out/ and exits 1, after every line is printed", () => {
  const fx = ready();
  const r = exec(render, fx, [fx.dir], {
    CREATIVE_VIDEO_FAKE_PROBE: JSON.stringify({ peak: -0.5 }),
  });
  assert.equal(r.code, 1);
  assert.match(
    r.out,
    /^delivery true peak: fail: -0\.5 dBTP vs at most -1 dBTP$/m,
  );
  for (const c of CHECKS.slice(0, -1))
    assert.ok(r.out.includes(`delivery ${c}: pass\n`), c);
  assert.ok(!r.out.includes("delivered:"));
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
  assert.ok(!fs.existsSync(path.join(fx.dir, "manifest.json")));
});

// Each window's edge passes and the first value past it fails: true peak at
// most -1 dBTP, loudness within 1 LU of -14 LUFS, duration within 0.25 s.
test("a delivery check passes at its edge and fails just past it", () => {
  const fx = ready();
  const total = readJson(path.join(fx.dir, "timeline.json")).total;
  const at = (probe, check) => {
    const r = exec(render, fx, [fx.dir], {
      CREATIVE_VIDEO_FAKE_PROBE: JSON.stringify(probe),
    });
    return r.out.match(new RegExp(`^delivery ${check}: (.*)$`, "m"))[1];
  };
  assert.equal(at({ peak: -1 }, "true peak"), "pass");
  assert.match(at({ peak: -0.9 }, "true peak"), /^fail: /);
  assert.equal(at({ lufs: -15 }, "loudness"), "pass");
  assert.equal(at({ lufs: -13 }, "loudness"), "pass");
  assert.equal(
    at({ lufs: -15.1 }, "loudness"),
    "fail: -15.1 LUFS vs -14 LUFS within 1 LU",
  );
  assert.equal(at({ duration: total + 0.249 }, "duration"), "pass");
  assert.match(at({ duration: total + 0.251 }, "duration"), /^fail: /);
  assert.match(at({ duration: total - 0.251 }, "duration"), /^fail: /);
});

test("an over.html and kit files authored after the timing stage reach the root that hf and the render use", () => {
  const fx = ready();
  author(fx, ["over"]);
  fs.mkdirSync(project(fx, "kit"), { recursive: true });
  fs.writeFileSync(project(fx, "kit", "look.css"), "");
  assert.equal(exec(hf, fx, [fx.dir, "check"]).code, 0);
  const html = read(project(fx, "index.html"));
  assert.ok(html.includes('id="over"'));
  assert.ok(html.includes('href="kit/look.css"'));
  fs.writeFileSync(project(fx, "kit", "devices.js"), "");
  fs.rmSync(project(fx, "index.html"));
  assert.equal(exec(render, fx).code, 0);
  assert.ok(read(project(fx, "index.html")).includes('src="kit/devices.js"'));
});

test("a video of the wrong frame rate fails that check and nothing is delivered", () => {
  const fx = ready();
  const r = exec(render, fx, [fx.dir], {
    CREATIVE_VIDEO_FAKE_PROBE: JSON.stringify({ fps: 25 }),
  });
  assert.equal(r.code, 1);
  assert.match(r.out, /^delivery frame rate: fail: 25 vs 30$/m);
  assert.ok(r.out.includes("delivery resolution: pass\n"));
  assert.ok(!fs.existsSync(path.join(fx.dir, "out")));
});

test("a render without the timing stage, or after the voice changed, is refused", () => {
  const fx = voiced();
  assert.match(
    exec(render, fx).err,
    /^render: timeline\.json is missing: run render\/timing\.mjs first/,
  );
  fs.writeFileSync(path.join(fx.dir, "timeline.json"), "{}");
  assert.match(
    exec(render, fx).err,
    /^render: timeline\.json: voice is not text/,
  );
  assert.equal(exec(timing, fx).code, 0);
  author(fx, ids);
  const voice = path.join(fx.dir, "voice.json");
  fs.appendFileSync(voice, "\n");
  const r = exec(render, fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^render: timeline\.json is from an older voice\.json: run render\/timing\.mjs again/,
  );
  assert.ok(!calls(fx).some((c) => c.call === "hyperframes"));
});

test("a scene file the agent has not written is refused by name before any render", () => {
  const fx = voiced();
  assert.equal(exec(timing, fx).code, 0);
  author(fx, ["context"]);
  const r = exec(render, fx);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^render: no compositions\/hook\.html, compositions\/recap\.html/,
  );
  assert.ok(!calls(fx).some((c) => c.call === "hyperframes"));
});

test("a stale out/ is cleared before the render", () => {
  const fx = ready();
  fs.mkdirSync(path.join(fx.dir, "out"));
  fs.writeFileSync(path.join(fx.dir, "out", "old.mp4"), "old");
  assert.equal(exec(render, fx).code, 0);
  assert.ok(!fs.existsSync(path.join(fx.dir, "out", "old.mp4")));
});

test("hf runs the HyperFrames CLI in the project with the output inherited", () => {
  const fx = ready();
  const r = exec(hf, fx, [fx.dir, "check", "--json"]);
  assert.equal(r.code, 0, r.err);
  const call = calls(fx).find((c) => c.call === "hyperframes");
  assert.deepEqual(call.args, ["check", "--json"]);
  assert.equal(call.cwd, project(fx));
  assert.equal(call.stdio, "inherit");
  assert.equal(call.env.HYPERFRAMES_NO_TELEMETRY, "1");
});

test("hf without a timeline or arguments is refused, with a usage exit for the missing arguments", () => {
  const fx = voiced();
  const r = exec(hf, fx, [fx.dir, "check"]);
  assert.equal(r.code, 1);
  assert.match(
    r.err,
    /^hf: timeline\.json is missing: run render\/timing\.mjs first/,
  );
  const u = exec(hf, fx, [fx.dir]);
  assert.equal(u.code, 2);
  assert.match(u.err, /^usage: node hf\.mjs <run-folder> <hyperframes args>/);
});
