// The render stage through its process door: a run folder compiled and voiced
// with the canned backend, a tool cache and font store laid out in a temp dir,
// and assertions on the composition, captions, delivery, caches and manifest.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { judged } from "./critic.mjs";
import { userDirs } from "../../skills/explainer-video/scripts/lib/paths.mjs";
import {
  catalogue,
  dest,
  lockHash,
} from "../../skills/explainer-video/scripts/lib/tools.mjs";
import { SLIDE } from "./fake-backend.mjs";
import { ARABIC, DIAGRAMS, SCRIPT } from "./scene-file.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const skill = path.join(here, "..", "..", "skills", "explainer-video");

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

// A temp machine: tool cache and font store as setup leaves them, a videos
// folder, and a project holding explainers/demo/script.md.
function fixture(text = SCRIPT) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-render-"));
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

// compile and voice, then render, a clean critic round taken when the critic
// alone holds the render.
function render(fx, extra) {
  for (const s of ["script/compile.mjs", "voice/voice.mjs"]) {
    const r = stage(fx, s);
    assert.equal(r.code, 0, `${s}: ${r.out}${r.err}`);
  }
  return judged(fx.dir, () => stage(fx, "render/render.mjs", extra));
}

const calls = (fx, name = "hyperframes") =>
  fs.existsSync(fx.log)
    ? fs
        .readFileSync(fx.log, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
        .filter((c) => c.call === name)
    : [];
const read = (...p) => fs.readFileSync(path.join(...p), "utf8");
const comp = (fx, f = "index.html") => read(fx.dir, "composition", f);
const unescape = (s) =>
  s
    .replace(/<[^>]+>/g, "")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&amp;", "&");
const seconds = (t) => {
  const [h, m, s] = t.replace(",", ".").split(":");
  return +h * 3600 + +m * 60 + +s;
};
const delivered = (fx) =>
  path.join(fx.tmp, "videos", "explainer-video", "proj", "demo");

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
  assert.ok(
    Math.abs(last.duration - (voiced.duration + 1)) < 0.002,
    "1 s hold",
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
  assert.match(r.held.out, /^gates: 5 pass, 0 fail, 1 pending; next: /m);
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

// Style profile lookup: the script names no style, so the stores decide.
const unstyled = SCRIPT.replace("style: claude-code\n", "");
const profile = (label, colors = {}) => {
  const p = JSON.parse(read(skill, "styles", "claude-code.json"));
  return JSON.stringify({ ...p, label, colors: { ...p.colors, ...colors } });
};
const put = (dir, name, body) => {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, name), body);
};
const own = (fx) => JSON.parse(read(fx.dir, "style.json"));

test("with no default named anywhere the run takes the bundled claude-code and copies it into the run", () => {
  const fx = fixture(unstyled);
  assert.equal(render(fx).code, 0);
  assert.equal(own(fx).name, "claude-code");
  assert.equal(
    JSON.parse(read(fx.dir, "manifest.json")).profile,
    "claude-code",
  );
});

test("a store's default file is honoured, and the project store beats the user store", () => {
  const fx = fixture(unstyled);
  const user = path.join(fx.tmp, "config", "explainer-video", "styles");
  put(user, "default", "mine\n");
  put(user, "mine.json", profile("user"));
  assert.equal(render(fx).code, 0);
  assert.equal(own(fx).name, "mine");
  assert.equal(own(fx).label, "user");

  const fx2 = fixture(unstyled);
  const user2 = path.join(fx2.tmp, "config", "explainer-video", "styles");
  put(user2, "default", "mine\n");
  put(user2, "mine.json", profile("user"));
  put(
    path.join(fx2.tmp, "proj", "explainers", ".styles"),
    "mine.json",
    profile("project"),
  );
  assert.equal(render(fx2).code, 0);
  assert.equal(own(fx2).label, "project");
});

test("a font only the profile carries is refused until setup's install lands it, then renders", () => {
  const fx = fixture();
  for (const s of ["script/compile.mjs", "voice/voice.mjs"])
    assert.equal(stage(fx, s).code, 0, s);
  const lora = {
    id: "font:lora",
    kind: "font",
    family: "lora",
    class: "serif",
    version: "5.3.0",
    files: ["latin-400-normal"],
    licence: "OFL-1.1",
  };
  styled(
    fx,
    {},
    {
      fonts: [lora],
      type: { ...latin, title: { ...latin.title, font: "lora" } },
    },
  );
  const before = render(fx);
  assert.equal(before.code, 1, before.out + before.err);
  assert.match(
    before.err,
    /^render: font:lora is not installed: run \/explainer-video setup/m,
  );
  // What `setup install` writes for the row: its files, then the stamp.
  const dir = dest(lora, fx.dirs);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "latin-400-normal.woff2"), "woff2");
  fs.writeFileSync(path.join(dir, ".stamp"), "");
  const after = render(fx);
  assert.equal(after.code, 0, after.out + after.err);
});

test("the run keeps its own style.json after the store's copy is edited", () => {
  const fx = fixture(unstyled);
  const project = path.join(fx.tmp, "proj", "explainers", ".styles");
  put(project, "default", "mine");
  put(project, "mine.json", profile("first"));
  assert.equal(render(fx).code, 0);
  put(project, "mine.json", profile("edited"));
  assert.equal(render(fx).code, 0);
  assert.equal(own(fx).label, "first");
});

test("a profile with a pair under its contrast floor refuses the run by name before any render", () => {
  const fx = fixture(unstyled);
  const project = path.join(fx.tmp, "proj", "explainers", ".styles");
  put(project, "default", "pale");
  put(project, "pale.json", profile("pale", { muted: "#c8c8c0" }));
  const r = render(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^render: style profile pale fails contrast: .*muted on bg [\d.]+:1, floor 4\.5:1/m,
  );
  assert.equal(calls(fx).length, 0);
  assert.ok(!fs.existsSync(path.join(fx.dir, "style.json")));
});

test("a narration edit that keeps the word count still asks for the voice stage again", () => {
  const fx = fixture();
  assert.equal(render(fx).code, 0);
  put(
    fx.dir,
    "script.md",
    SCRIPT.replace("It reads the issue.", "It ignores the issue."),
  );
  assert.equal(stage(fx, "script/compile.mjs").code, 0);
  const r = stage(fx, "render/render.mjs");
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^render: voice\.json does not match scene steps: run the voice stage again/m,
  );
});

// A WAV header field rewritten in place, 16-bit or 32-bit little-endian.
const patchWav = (fx, scene, at, value, bits = 16) => {
  const v = JSON.parse(read(fx.dir, "voice.json")).scenes[scene];
  const f = path.join(fx.dir, v.audio);
  const b = fs.readFileSync(f);
  if (bits === 16) b.writeUInt16LE(value, at);
  else b.writeUInt32LE(value, at);
  fs.writeFileSync(f, b);
};
// A project profile `odd` the script names, then compiled.
const styled = (fx, colors, extra) => {
  const p = JSON.parse(profile("odd", colors));
  put(
    path.join(fx.tmp, "proj", "explainers", ".styles"),
    "odd.json",
    JSON.stringify({ ...p, ...extra }),
  );
  put(fx.dir, "script.md", SCRIPT.replace("style: claude-code", "style: odd"));
  assert.equal(stage(fx, "script/compile.mjs").code, 0);
};
const latin = JSON.parse(read(skill, "styles", "claude-code.json")).type;

for (const [name, arrange, why, voiced = true] of [
  [
    "a run with no compiled script",
    () => {},
    /^render: no script\.json: run the compile stage first/m,
    false,
  ],
  [
    "a setup row that is not installed",
    (fx) =>
      fs.rmSync(
        path.join(
          dest(
            catalogue().find((r) => r.id === "font:inter"),
            fx.dirs,
          ),
          ".stamp",
        ),
      ),
    /^render: font:inter is not installed: run \/explainer-video setup/m,
  ],
  [
    "a font folder that holds the stamp but lacks one of its files",
    (fx) => {
      const row = catalogue().find((r) => r.id === "font:inter");
      fs.rmSync(path.join(dest(row, fx.dirs), `${row.files[0]}.woff2`));
    },
    /^render: font:inter lacks latin-\d+-normal\.woff2: run \/explainer-video setup/m,
  ],
  [
    "a language with no render fonts",
    (fx) => {
      put(fx.dir, "script.md", SCRIPT.replace("language: en", "language: de"));
      assert.equal(stage(fx, "script/compile.mjs").code, 0);
    },
    /^render: no render fonts for language de/m,
    false,
  ],
  [
    "a profile in a layout this version does not draw",
    (fx) => styled(fx, {}, { layout: "grid" }),
    /^render: style profile odd: this version draws layout bands with motion rise, not grid with rise/m,
    false,
  ],
  [
    "a profile naming a font no setup row installs",
    (fx) =>
      styled(
        fx,
        {},
        { type: { ...latin, text: { font: "comic", weight: 400 } } },
      ),
    /^render: style profile odd names font comic, which no setup row installs/m,
  ],
  [
    "a profile with no text font",
    (fx) => styled(fx, {}, { type: { ...latin, text: undefined } }),
    /^render: style profile odd names no text font/m,
  ],
  [
    "a contrast floor that is not a number",
    (fx) => styled(fx, {}, { gates: { contrast: { body: "bogus" } } }),
    /^render: style profile odd fails contrast: gates\.contrast\.body: not a number/m,
    false,
  ],
  [
    "a profile that lowers a contrast floor",
    (fx) => styled(fx, {}, { gates: { contrast: { body: 3 } } }),
    /^render: style profile odd: gates\.contrast\.body 3 lowers the skill's floor 4\.5$/m,
    false,
  ],
  [
    "a profile that loosens the peak floor",
    (fx) => styled(fx, {}, { gates: { loudness: { peak: 0 } } }),
    /^render: style profile odd: gates\.loudness\.peak 0 lowers the skill's floor -1$/m,
    false,
  ],
  [
    "a profile that allows more sound effects a minute",
    (fx) => styled(fx, {}, { gates: { sfx: { perMinute: 30 } } }),
    /^render: style profile odd: gates\.sfx\.perMinute 30 lowers the skill's floor 24$/m,
    false,
  ],
  [
    "a negative sound effect floor",
    (fx) => styled(fx, {}, { gates: { sfx: { perMinute: -1 } } }),
    /^render: style profile odd: gates\.sfx\.perMinute -1 must be a whole number 0 or more$/m,
    false,
  ],
  [
    "a fractional sound effect floor",
    (fx) => styled(fx, {}, { gates: { sfx: { perMinute: 0.5 } } }),
    /^render: style profile odd: gates\.sfx\.perMinute 0\.5 must be a whole number 0 or more$/m,
    false,
  ],
  [
    "a loudness tolerance of zero",
    (fx) => styled(fx, {}, { gates: { loudness: { tolerance: 0 } } }),
    /^render: style profile odd: gates\.loudness\.tolerance 0 must be above 0$/m,
    false,
  ],
  [
    "a peak floor under what the master can aim beneath",
    (fx) => styled(fx, {}, { gates: { loudness: { peak: -9 } } }),
    /^render: style profile odd: gates\.loudness\.peak -9 is under -8\.5, the lowest the master reaches$/m,
    false,
  ],
  [
    "a profile naming a floor the skill has not",
    (fx) => styled(fx, {}, { gates: { layout: { width: 2 } } }),
    /^render: style profile odd: gates\.layout\.width: no such floor$/m,
    false,
  ],
  [
    "a profile naming a gate group the skill has not",
    (fx) => styled(fx, {}, { gates: { motion: { speed: 2 } } }),
    /^render: style profile odd: gates\.motion: no such floor$/m,
    false,
  ],
  [
    "a layout floor that is not a number",
    (fx) => styled(fx, {}, { gates: { layout: { textPx: "big" } } }),
    /^render: style profile odd: gates\.layout\.textPx: not a number$/m,
    false,
  ],
  [
    "a profile colour that is not #rrggbb",
    (fx) => styled(fx, { muted: "grey" }),
    /^render: style profile odd fails contrast: muted on bg: not a #rrggbb colour/m,
    false,
  ],
  [
    "a scene WAV that is not mono PCM",
    (fx) => patchWav(fx, 0, 22, 2),
    /^render: \.cache\/voice\/\w+\.wav is not 16-bit mono PCM: run the voice stage again/m,
  ],
  [
    "scene WAVs at different sample rates",
    (fx) => patchWav(fx, 1, 24, 8000, 32),
    /^render: the scenes' WAVs differ in sample rate: run the voice stage again/m,
  ],
]) {
  test(`render refuses ${name} by name, before any HyperFrames call`, () => {
    const fx = fixture();
    if (voiced)
      for (const s of ["script/compile.mjs", "voice/voice.mjs"])
        assert.equal(stage(fx, s).code, 0, s);
    arrange(fx);
    const r = stage(fx, "render/render.mjs");
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.err, why);
    assert.equal(calls(fx).length, 0);
  });
}

// A scene file's tweens: [selector, from, to, seconds into the scene].
const tweens = (fx, id) =>
  JSON.parse(
    comp(fx, `scenes/${id}.html`).match(/const tweens = (\[.*\]);/)[1],
  );
const at = (fx, id, n) => {
  const s = JSON.parse(read(fx.dir, "timeline.json")).scenes.find(
    (s) => s.id === id,
  );
  return s.sentences[n - 1] - s.start;
};
const near = (a, b) => Math.abs(a - b) < 0.002;
const profiled = (fx, name, extra) =>
  put(
    path.join(fx.tmp, "proj", "explainers", ".styles"),
    `${name}.json`,
    JSON.stringify({
      ...JSON.parse(read(skill, "styles", "claude-code.json")),
      ...extra,
    }),
  );

test("each diagram and code component composes onto its scene's paused timeline, each reveal at its sentence, nothing on the clock", () => {
  const fx = fixture(DIAGRAMS);
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  for (const id of ["flow", "sides", "gates", "code", "diff"]) {
    const html = comp(fx, `scenes/${id}.html`);
    assert.doesNotMatch(
      html,
      /transition|animation|@keyframes|setTimeout|setInterval|requestAnimationFrame|Date\.now|performance\.now|Math\.random/,
      id,
    );
    assert.match(html, /gsap\.timeline\(\{ paused: true \}\)/, id);
    assert.ok(tweens(fx, id).length, id);
    // Every scoped line opens a rule: a bare selector swallows the page's
    // next rule, as a clean look's empty sketch CSS once did.
    const style = html.match(/<style>([\s\S]*?)<\/style>/)[1];
    for (const l of style.split("\n").filter((l) => l.trim()))
      assert.match(l, /\{/, `${id}: ${l}`);
  }

  const flow = comp(fx, "scenes/flow.html");
  assert.equal([...flow.matchAll(/class="node /g)].length, 3);
  assert.equal([...flow.matchAll(/class="arrow /g)].length, 2);
  const steps = tweens(fx, "flow").filter(([s]) => /^\.n\d$/.test(s));
  assert.deepEqual(
    steps.map(([s, , , t]) => [s, near(t, at(fx, "flow", +s.slice(2) + 1))]),
    [
      [".n0", true],
      [".n1", true],
      [".n2", true],
    ],
  );
  // draw: the arrow into a step strokes on as that step rises.
  const drawn = tweens(fx, "flow").filter(([, f]) => "strokeDashoffset" in f);
  assert.equal(drawn.length, 2);
  assert.ok(near(drawn[1][3], at(fx, "flow", 3)));

  for (const id of ["flow", "sides", "gates"])
    assert.match(comp(fx, `scenes/${id}.html`), /class="content" dir="ltr"/);

  // Shiki colours each token from the profile's palette; code stays left to
  // right whatever the scene's direction.
  const code = comp(fx, "scenes/code.html");
  // (the critic's round renders a second time)
  assert.deepEqual(
    calls(fx, "highlight")
      .slice(0, 3)
      .map((c) => c.lang),
    ["bash", "js", "js"],
  );
  assert.match(code, /<span style="color:var\(--code-[a-z-]+\)">/);
  assert.match(code, /--code-token-keyword: var\(--accent\);/);
  assert.match(code, /class="code rt" dir="ltr"/);
  const bar = tweens(fx, "code").find(([s]) => s === ".hl0");
  assert.ok(near(bar[3], at(fx, "code", 2)));

  // The diff: the removed line closes and the added one opens at sentence 2,
  // by tweens on the timeline, the kept lines untouched.
  const diff = tweens(fx, "diff");
  const del = diff.filter(([s]) => s.startsWith(".del"));
  const add = diff.filter(([s]) => s.startsWith(".add"));
  assert.equal(del.length, 1);
  assert.equal(add.length, 1);
  assert.equal(del[0][2].height, 0);
  assert.equal(add[0][1].height, 0);
  for (const [, , , t] of [...del, ...add])
    assert.ok(near(t, at(fx, "diff", 2)), String(t));
  const rows = comp(fx, "scenes/diff.html");
  assert.match(rows, /class="ln del del0">.*a - b;/);
  assert.match(rows, /class="ln add add0">.*a \+ b;/);
});

test("a seeded sketch renders identically twice, each outline at its own seed", () => {
  const twice = [0, 1].map(() => {
    const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: rough"));
    profiled(fx, "rough", { look: "sketch" });
    const r = render(fx);
    assert.equal(r.code, 0, r.out + r.err);
    return {
      scenes: ["flow", "sides"].map((id) => comp(fx, `scenes/${id}.html`)),
      seeds: calls(fx, "sketch").flatMap((c) => c.shapes.map((s) => s.seed)),
    };
  });
  assert.deepEqual(twice[0], twice[1]);
  for (const s of twice[0].scenes) assert.match(s, /<svg class="sk"/);
  // three nodes, two arrows and two panels, each at its own seed
  assert.equal(new Set(twice[0].seeds).size, 7);
  assert.ok(twice[0].seeds.every((s) => Number.isInteger(s) && s > 0));
});

test("a right-to-left scene mirrors its flow and keeps its code left to right", async () => {
  process.env.EXPLAINER_VIDEO_FAKE_LOG = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "ev-rtl-")),
    "calls.jsonl",
  );
  const { sceneFile } =
    await import("../../skills/explainer-video/scripts/render/compose.mjs");
  const backend = await import("./fake-backend.mjs");
  const profile = JSON.parse(read(skill, "styles", "claude-code.json"));
  const timing = { duration: 6, sentences: [0.2, 2, 4] };
  const scene = (component, props) => ({
    id: component,
    visual: { component, props },
  });
  const flow = await sceneFile(
    scene("flow", {
      steps: [
        { at: 1, label: "Issue" },
        { at: 2, label: "Test" },
      ],
    }),
    timing,
    profile,
    { backend, dir: "rtl" },
  );
  assert.match(flow, /class="content" dir="rtl"/);
  assert.match(
    flow,
    /\[data-composition-id="flow"\] \[dir="rtl"\] \.arrow svg \{ transform: scaleX\(-1\); \}/,
  );
  const code = await sceneFile(
    scene("code", { lang: "js", code: "let a = 1;" }),
    timing,
    profile,
    { backend, dir: "rtl" },
  );
  assert.match(code, /class="content" dir="rtl"/);
  assert.match(code, /class="code rt" dir="ltr"/);
});

test("a profile that disallows an effect keeps it out of the composition", () => {
  const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: plain"));
  profiled(fx, "plain", { effects: [] });
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.ok(!tweens(fx, "flow").some(([, f]) => "strokeDashoffset" in f));
  assert.doesNotMatch(comp(fx, "scenes/flow.html"), /stroke-dasharray/);
  assert.ok(!tweens(fx, "code").some(([s]) => s.startsWith(".hl")));
  assert.doesNotMatch(comp(fx, "scenes/code.html"), /class="hl /);
});

for (const [name, extra, why] of [
  [
    "an unknown effect",
    { effects: ["draw", "confetti"] },
    /^render: style profile odd: effects: confetti is not an effect \(draw, highlight\)/m,
  ],
  [
    "an unknown look",
    { look: "neon" },
    /^render: style profile odd: look neon is not clean or sketch/m,
  ],
]) {
  test(`a profile naming ${name} refuses the run by name before any render`, () => {
    const fx = fixture(DIAGRAMS.replace("style: claude-code", "style: odd"));
    profiled(fx, "odd", extra);
    const r = render(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(r.err, why);
    assert.equal(calls(fx).length, 0);
  });
}

test("a draft naming a family no setup row installs renders it from the font store its draft fetched it into", () => {
  const fx = fixture();
  const env = {
    ...fx.env,
    EXPLAINER_VIDEO_FAKE_PRESENT: "ffmpeg",
    EXPLAINER_VIDEO_FAKE_SITE: JSON.stringify({
      "https://acme.test/": {
        pages: [SLIDE],
        colors: [],
        fonts: [{ role: "text", stack: "'Noto Serif', serif" }],
      },
    }),
  };
  const acme = path.join(fx.tmp, "proj", "explainers", "acme");
  const style = (script, ...args) =>
    spawnSync(
      process.execPath,
      [path.join(skill, "scripts", "style", script), acme, ...args],
      { env, encoding: "utf8" },
    );
  let r = style("measure.mjs", "https://acme.test/");
  assert.equal(r.status, 0, r.stderr);
  put(
    path.join(acme, "style-draft"),
    "roles.json",
    JSON.stringify({
      bg: { candidate: "s1", why: "ground" },
      text: { candidate: "s3", why: "text" },
    }),
  );
  r = style("draft.mjs", "odd");
  assert.equal(r.status, 0, r.stderr);
  put(
    path.join(fx.tmp, "proj", "explainers", ".styles"),
    "odd.json",
    read(acme, "style-draft", "odd.json"),
  );
  put(fx.dir, "script.md", SCRIPT.replace("style: claude-code", "style: odd"));

  const done = render(fx);
  assert.equal(done.code, 0, done.out + done.err);
  assert.ok(
    fs
      .readdirSync(path.join(fx.dir, "composition", "fonts"))
      .includes("noto-serif-latin-400-normal.woff2"),
  );
  assert.match(comp(fx), /\.cue \{[^}]*font: 400 40px\/1\.3 "noto-serif"/);
});

test("an Arabic script renders right to left on its text boxes, its English terms whole and left to right", () => {
  const fx = fixture(ARABIC);
  fx.env.GEMINI_API_KEY = "test-key";
  const r = render(fx);
  assert.equal(r.code, 0, r.out + r.err);

  const index = comp(fx);
  assert.match(index, /<html lang="ar">/);
  assert.doesNotMatch(index, /<(html|body)[^>]* dir=/);
  assert.doesNotMatch(index, /id="root"[^>]* dir=/);
  assert.match(index, /<div class="header" dir="rtl">/);
  for (const family of ["noto-naskh-arabic", "ibm-plex-sans-arabic"])
    assert.match(index, new RegExp(`@font-face \\{ font-family: "${family}"`));
  assert.match(
    index,
    /\.cue \{[^}]*font: 400 40px\/1\.7 "ibm-plex-sans-arabic", "inter"/,
  );
  assert.match(index, /\.lat \{ font-family: "inter"; white-space: nowrap; \}/);
  const cues = [...index.matchAll(/<div class="cue clip"[^>]*>/g)];
  assert.ok(cues.length > 0);
  for (const [cue] of cues) assert.match(cue, / dir="rtl"/);
  // A multi-word term is one caption token, isolated, so it keeps its order.
  assert.match(
    index,
    /<span class="w" data-at="[\d.]+"><bdi class="lat">pull request<\/bdi><\/span>/,
  );

  const steps = comp(fx, "scenes/steps.html");
  assert.match(steps, /<div class="content" dir="rtl">/);
  assert.match(steps, /<bdi class="lat ti">branch<\/bdi>/);
  assert.match(steps, /\.label \{[^}]*"noto-naskh-arabic", "source-serif-4"/);
  const code = comp(fx, "scenes/code.html");
  assert.match(code, /<div class="code rt" dir="ltr">/);
  assert.doesNotMatch(code, /<bdi/);
  assert.match(
    comp(fx, "scenes/hook.html"),
    /<bdi class="lat ti">pull request<\/bdi>/,
  );
});
