// The voice stage through its process door: a run folder holding a script, the
// canned backend (fake audio that spells its text, a fake aligner model), and
// assertions on the files the stage writes, its verdict lines and exit code.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const voice = path.join(
  here,
  "..",
  "..",
  "skills",
  "explainer-video",
  "scripts",
  "voice",
  "voice.mjs",
);

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);

const SCENES = [
  {
    id: "hook",
    narration: ["Ship drives one issue to a merged pull request."],
  },
  {
    id: "context",
    narration: [
      "It reads the profile first.",
      "Then it claims the issue so no other run takes it.",
    ],
  },
  {
    id: "recap",
    narration: ["Every change lands through a reviewed pull request."],
  },
];

function fixture(scenes = SCENES, language = "en") {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-voice-"));
  temps.push(tmp);
  const dir = path.join(tmp, "explainers", "demo");
  fs.mkdirSync(dir, { recursive: true });
  const fx = { tmp, dir, log: path.join(tmp, "calls.jsonl") };
  write(fx, scenes, language);
  return fx;
}

const write = (fx, scenes, language = "en") =>
  fs.writeFileSync(
    path.join(fx.dir, "script.json"),
    JSON.stringify({ language, scenes }),
  );

function run(fx, extra = {}) {
  const r = spawnSync(process.execPath, [voice, fx.dir], {
    env: {
      ...extra,
      PATH: process.env.PATH,
      HOME: path.join(fx.tmp, "home"),
      XDG_CACHE_HOME: path.join(fx.tmp, "cache"),
      EXPLAINER_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
      EXPLAINER_VIDEO_FAKE_LOG: fx.log,
    },
    encoding: "utf8",
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

const synths = (fx) =>
  fs.existsSync(fx.log)
    ? fs
        .readFileSync(fx.log, "utf8")
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
        .filter((c) => c.call === "synthesize")
    : [];

const line = (out, id) =>
  out.split("\n").find((l) => l.startsWith(`voice ${id}:`));

// Seconds of 16-bit mono PCM in a WAV file, read from its header.
function wavSeconds(file) {
  const b = fs.readFileSync(file);
  assert.equal(b.toString("ascii", 0, 4), "RIFF");
  assert.equal(b.toString("ascii", 8, 12), "WAVE");
  const rate = b.readUInt32LE(24);
  return b.readUInt32LE(40) / 2 / rate;
}

test("a first run voices the whole narration in one call and writes a WAV and word timings per scene", () => {
  const fx = fixture();
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(synths(fx).length, 1);
  assert.equal(
    synths(fx)[0].text,
    SCENES.flatMap((s) => s.narration).join(" "),
  );
  assert.match(synths(fx)[0].model, /models\/kokoro-82m@1939ad2a8e41$/);
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  assert.equal(timeline.narrator, "bf_emma");
  assert.deepEqual(
    timeline.scenes.map((s) => s.id),
    SCENES.map((s) => s.id),
  );
  for (const [i, s] of timeline.scenes.entries()) {
    assert.match(line(r.out, s.id), /voiced/);
    const seconds = wavSeconds(path.join(fx.dir, s.audio));
    assert.ok(Math.abs(seconds - s.duration) < 0.01, `${s.id} duration`);
    const words = SCENES[i].narration.join(" ").split(" ");
    assert.deepEqual(
      s.words.map((w) => w.text),
      words,
    );
    let t = 0;
    for (const w of s.words) {
      assert.ok(w.start >= t && w.end > w.start, JSON.stringify(w));
      t = w.end;
    }
    assert.ok(t <= s.duration);
  }
});

test("changing one scene's text re-voices only that scene; the others are cache hits", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  const changed = structuredClone(SCENES);
  changed[1].narration[1] =
    "Then it takes the issue so no other run claims it.";
  write(fx, changed);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(line(r.out, "hook"), /: cached ·/);
  assert.match(line(r.out, "context"), /: voiced ·/);
  assert.match(line(r.out, "recap"), /: cached ·/);
  assert.match(r.out, /3 scene\(s\), 1 voiced in 1 call\(s\), 2 cached/);
  const calls = synths(fx);
  assert.equal(calls.length, 2);
  assert.equal(calls[1].text, changed[1].narration.join(" "));
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  assert.equal(timeline.scenes[1].words[7].text, "takes");
});

test("a scene whose cached WAV is gone is voiced again, not reported cached", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  fs.rmSync(path.join(fx.dir, timeline.scenes[0].audio));
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(line(r.out, "hook"), /: voiced ·/);
  assert.match(line(r.out, "context"), /: cached ·/);
  assert.ok(fs.existsSync(path.join(fx.dir, timeline.scenes[0].audio)));
});

test("a scene with no narration is refused by name before anything is voiced", () => {
  const scenes = structuredClone(SCENES);
  scenes[1].narration = [];
  const fx = fixture(scenes);
  const r = run(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /scene context has no narration/);
  assert.equal(synths(fx).length, 0);
});

// Each misrender the fake can make, the floor it misses, and the value the
// verdict line must carry: worked from the fake's frame layout.
for (const [name, sentence, why] of [
  [
    "a garbled render",
    "This garbled sentence comes out as noise.",
    /recall 0 under 0\.8/,
  ],
  [
    "a looped render",
    "This looped sentence plays its words twice.",
    /precision 0\.5 under 0\.85/,
  ],
  [
    "a dragged render",
    "This sentence reads slowly.",
    /rate \d+(\.\d+)? chars\/s outside 9 to 22/,
  ],
]) {
  test(`voice QC blocks ${name} with the measured value, writes no timeline and caches nothing for it`, () => {
    const scenes = structuredClone(SCENES);
    scenes[2].narration = [sentence];
    const fx = fixture(scenes);
    const r = run(fx);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(line(r.out, "recap"), /· fail: /);
    assert.match(line(r.out, "recap"), why);
    assert.match(line(r.out, "hook"), /· pass$/);
    assert.match(r.out, /^voice QC failed: 1 scene\(s\)/m);
    assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
    const again = run(fx);
    assert.match(line(again.out, "recap"), /: voiced ·/);
    assert.match(line(again.out, "hook"), /: cached ·/);
  });
}

// #725: a failed scene kept no record of what the aligner heard, so the
// misheard word had to be guessed.
test("a failed scene keeps what the aligner heard beside its voice outputs and names it", () => {
  const scenes = structuredClone(SCENES);
  scenes[2].narration = ["This looped sentence plays its words twice."];
  const fx = fixture(scenes);
  const r = run(fx);
  assert.equal(r.code, 1, r.out + r.err);
  const m = line(r.out, "recap").match(
    /heard: (\.cache\/voice\/\w+\.heard\.txt)$/,
  );
  assert.ok(m, line(r.out, "recap"));
  assert.equal(
    fs.readFileSync(path.join(fx.dir, m[1]), "utf8").trim(),
    "this looped sentence plays its words twice this looped sentence plays its words twice",
  );
});

test("a rerun that fails QC removes the timeline the last pass wrote", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  const scenes = structuredClone(SCENES);
  scenes[2].narration = ["This garbled sentence comes out as noise."];
  write(fx, scenes);
  assert.equal(run(fx).code, 1);
  assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
});

test("a rerun refused for its input removes the timeline the last pass wrote", () => {
  const fx = fixture();
  assert.equal(run(fx).code, 0);
  fs.writeFileSync(
    path.join(fx.dir, "script.json"),
    JSON.stringify({ language: "en", narrator: "nobody", scenes: SCENES }),
  );
  const r = run(fx);
  assert.equal(r.code, 1);
  assert.match(r.err, /no narrator nobody/);
  assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
});

// Five scenes, the i-th of `n[i]` sentences, or each of `n[0]`; the fake voices
// a sentence in about 2.95 s, so four a scene voice about 59 s, six 88.6 s,
// and 4, 4, 4, 3, 3 about 53.5 s.
const long = (...n) =>
  ["one", "two", "three", "four", "five"].map((w, i) => ({
    id: `scene-${w}`,
    narration: new Array(n[i] ?? n[0]).fill(
      `Scene ${w} reads the issue and then writes it.`,
    ),
  }));

test("with a brief, the voiced timeline and the closing hold must land within 10 percent of the brief's length", () => {
  const fx = fixture(long(4));
  fs.writeFileSync(
    path.join(fx.dir, "brief.json"),
    JSON.stringify({ length: 1 }),
  );
  let r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(r.out, /^voice length: pass: the scenes voice /m);
  assert.ok(fs.existsSync(path.join(fx.dir, "voice.json")));

  write(fx, long(6));
  r = run(fx);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.out,
    /^voice length: fail: the scenes voice 88\.6 s \(scene-one 17\.5 s, scene-two 17\.4 s, scene-three 18\.1 s, scene-four 17\.8 s, scene-five 17\.9 s\) and the 1 s hold vs the brief's 60 s ±10%$/m,
  );
  assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));

  // Short of the band by less than the hold: the hold brings it inside.
  write(fx, long(4, 4, 4, 3, 3));
  r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(
    r.out,
    /^voice length: pass: the scenes voice 53\.5 s \(scene-one 11\.7 s, scene-two 11\.6 s, scene-three 12\.1 s, scene-four 9\.1 s, scene-five 9\.1 s\) and the 1 s hold vs the brief's 60 s ±10%$/m,
  );
});

test("with no brief, as when voicing a narration alone, no length is checked", () => {
  const fx = fixture(long(6));
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.doesNotMatch(r.out, /^voice length:/m);
});

test("voice on a mistyped run folder says which stage to run and writes nothing", () => {
  const fx = fixture();
  const r = run({ ...fx, dir: path.join(fx.tmp, "typo") });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^voice: no script\.json: run the compile stage first/m);
  assert.ok(!fs.existsSync(path.join(fx.tmp, ".gitignore")));
  assert.ok(!fs.existsSync(path.join(fx.tmp, "typo")));
});

test("two scenes with the same narration share one WAV that matches both entries", () => {
  const fx = fixture([SCENES[0], { ...SCENES[0], id: "again" }, SCENES[2]]);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  for (const s of timeline.scenes) {
    const seconds = wavSeconds(path.join(fx.dir, s.audio));
    assert.ok(Math.abs(seconds - s.duration) < 0.01, `${s.id} duration`);
  }
});

test("a narration of function words only passes QC when the transcript matches", () => {
  const scenes = structuredClone(SCENES);
  scenes[1].narration = ["Here we are."];
  const fx = fixture(scenes);
  const r = run(fx);
  assert.equal(r.code, 0, r.out + r.err);
  assert.match(line(r.out, "context"), /· pass$/);
});

// Egyptian Arabic narration with English terms kept in Latin letters, as the
// script stage writes it; the default Arabic narrator is a Gemini voice.
const AR_SCENES = [
  {
    id: "hook",
    narration: ["شيب بياخد مهمة واحدة ويوصلها لحد pull request متراجع."],
  },
  {
    id: "context",
    narration: [
      "الأول بيقرا الـ profile بتاع الريبو.",
      "بعدين بيعمل branch جديد ويشغل الـ CI.",
    ],
  },
  {
    id: "recap",
    narration: ["كل تغيير بيدخل من خلال review قبل الـ merge."],
  },
];
const KEY = { GEMINI_API_KEY: "test-key" };

test("an Arabic script voices in one Gemini call, passes QC and times every word", () => {
  const fx = fixture(AR_SCENES, "ar");
  const r = run(fx, KEY);
  assert.equal(r.code, 0, r.out + r.err);
  const calls = synths(fx);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].backend, "gemini");
  assert.equal(calls[0].voice, "ar-eg-csagent-2");
  assert.equal(calls[0].text, AR_SCENES.flatMap((s) => s.narration).join(" "));
  const timeline = JSON.parse(
    fs.readFileSync(path.join(fx.dir, "voice.json"), "utf8"),
  );
  assert.equal(timeline.narrator, "ar-eg-csagent-2");
  for (const [i, s] of timeline.scenes.entries()) {
    assert.match(line(r.out, s.id), /recall 1 · precision 1 · .* · pass$/);
    assert.deepEqual(
      s.words.map((w) => w.text),
      AR_SCENES[i].narration.join(" ").split(" "),
    );
    let t = 0;
    for (const w of s.words) {
      assert.ok(w.start >= t && w.end > w.start, JSON.stringify(w));
      t = w.end;
    }
  }
});

for (const [name, sentence, why] of [
  ["a garbled", "الجملة دي طالعة مشوش خالص.", /recall 0 under 0\.8/],
  ["a looped", "الجملة دي مكرر كلامها مرتين.", /precision 0\.5 under 0\.85/],
  [
    "a dragged",
    "الجملة دي بتتقري ببطء.",
    /rate \d+(\.\d+)? chars\/s outside 9 to 22/,
  ],
]) {
  test(`voice QC blocks ${name} Arabic render with the measured value`, () => {
    const scenes = structuredClone(AR_SCENES);
    scenes[2].narration = [sentence];
    const fx = fixture(scenes, "ar");
    const r = run(fx, KEY);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(line(r.out, "recap"), why);
    assert.match(line(r.out, "hook"), /· pass$/);
    assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
  });
}

test("a Gemini narrator with no GEMINI_API_KEY is refused with where to get one, before any synthesis", () => {
  for (const extra of [{}, { GEMINI_API_KEY: "" }]) {
    const fx = fixture(AR_SCENES, "ar");
    const r = run(fx, extra);
    assert.equal(r.code, 1, r.out + r.err);
    assert.match(
      r.err,
      /^voice: narrator ar-eg-csagent-2 needs GEMINI_API_KEY: get a free key at https:\/\/aistudio\.google\.com\/apikey, or choose another narrator in the brief$/m,
    );
    assert.equal(synths(fx).length, 0);
  }
});

test("a narrator who does not speak the script's language is refused before any synthesis", () => {
  const fx = fixture(AR_SCENES, "ar");
  fs.writeFileSync(
    path.join(fx.dir, "script.json"),
    JSON.stringify({ language: "ar", narrator: "bf_emma", scenes: AR_SCENES }),
  );
  const r = run(fx, KEY);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(r.err, /^voice: no narrator bf_emma for ar$/m);
  assert.equal(synths(fx).length, 0);
});

test("two changed scenes with the same narration cost one Gemini call on a rerun", () => {
  const fx = fixture(AR_SCENES, "ar");
  assert.equal(run(fx, KEY).code, 0);
  const changed = structuredClone(AR_SCENES);
  changed[0].narration = changed[2].narration = [
    "كل تغيير بيعدي على review قبل الـ merge.",
  ];
  write(fx, changed, "ar");
  const r = run(fx, KEY);
  assert.equal(r.code, 0, r.out + r.err);
  assert.equal(synths(fx).length, 2);
  assert.match(line(r.out, "hook"), /: voiced ·.*· pass$/);
  assert.match(line(r.out, "recap"), /: voiced ·.*· pass$/);
});

test("an English script with GEMINI_API_KEY set still voices on Kokoro", () => {
  const fx = fixture();
  const r = run(fx, KEY);
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(
    synths(fx).map((c) => [c.voice, c.backend]),
    [["bf_emma", undefined]],
  );
});

test("a Gemini quota stop keeps the scenes voiced before it, and the next run voices only the rest", () => {
  const fx = fixture(AR_SCENES, "ar");
  assert.equal(run(fx, KEY).code, 0);
  const changed = structuredClone(AR_SCENES);
  changed[0].narration = [
    "شيب بياخد مهمة جديدة ويوصلها لحد pull request متراجع.",
  ];
  changed[2].narration = ["كل تغيير بيعدي على review قبل الـ merge."];
  write(fx, changed, "ar");
  const stopped = run(fx, { ...KEY, EXPLAINER_VIDEO_FAKE_QUOTA: "2" });
  assert.equal(stopped.code, 1, stopped.out + stopped.err);
  assert.match(
    stopped.err,
    /^voice: Gemini quota reached \(Gemini answered HTTP 429: You exceeded your current quota\); 1 scene\(s\) voiced before it are kept\. Voice again once the quota resets \(tomorrow, for a daily quota\), which voices only the missing scenes; use a paid key; or choose another narrator in the brief$/m,
  );
  assert.equal(synths(fx).length, 2);
  assert.ok(!fs.existsSync(path.join(fx.dir, "voice.json")));
  const resumed = run(fx, KEY);
  assert.equal(resumed.code, 0, resumed.out + resumed.err);
  assert.match(line(resumed.out, "hook"), /: cached ·/);
  assert.match(line(resumed.out, "context"), /: cached ·/);
  assert.match(line(resumed.out, "recap"), /: voiced ·/);
  assert.match(resumed.out, /3 scene\(s\), 1 voiced in 1 call\(s\), 2 cached/);
  const calls = synths(fx);
  assert.equal(calls.length, 3);
  assert.equal(calls[2].text, changed[2].narration.join(" "));
});

const ELEVEN = (fx) =>
  fs.writeFileSync(
    path.join(fx.dir, "script.json"),
    JSON.stringify({
      language: "en",
      narrator: "elevenlabs-george",
      scenes: SCENES,
    }),
  );

test("an ElevenLabs narrator with no ELEVENLABS_API_KEY is refused with where to get one, before any synthesis", () => {
  const fx = fixture();
  ELEVEN(fx);
  const r = run(fx, KEY);
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^voice: narrator elevenlabs-george needs ELEVENLABS_API_KEY: get a free key at https:\/\/elevenlabs\.io\/app\/settings\/api-keys, or choose another narrator in the brief$/m,
  );
  assert.equal(synths(fx).length, 0);
});

test("an ElevenLabs narrator with its key voices through the elevenlabs backend", () => {
  const fx = fixture();
  ELEVEN(fx);
  const r = run(fx, { ELEVENLABS_API_KEY: "test-key" });
  assert.equal(r.code, 0, r.out + r.err);
  assert.deepEqual(
    synths(fx).map((c) => [c.backend, c.voice]),
    [["elevenlabs", "JBFqnCBsd6RMkjVDRZzb"]],
  );
});

test("an ElevenLabs quota stop names ElevenLabs and keeps nothing it did not voice", () => {
  const fx = fixture();
  ELEVEN(fx);
  const r = run(fx, {
    ELEVENLABS_API_KEY: "test-key",
    EXPLAINER_VIDEO_FAKE_QUOTA: "0",
  });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^voice: ElevenLabs quota reached \(ElevenLabs answered HTTP 401: This request exceeds your quota limit\); 0 scene\(s\) voiced before it are kept\./m,
  );
  assert.equal(synths(fx).length, 0);
});

// The real backend on a stubbed fetch: ElevenLabs answers spent credits with
// 402 and `detail.code: "insufficient_credits"`, and its legacy answer is 400 or
// 401 with `detail.status: "quota_exceeded"` (backend.mjs cites both docs), not
// 429.
test("the real ElevenLabs backend reads spent credits as a quota stop and invalid_api_key as not one", async () => {
  const { synthesize } =
    await import("../../skills/explainer-video/scripts/lib/backend.mjs");
  const real = globalThis.fetch;
  const answer = (status, detail) => async () =>
    new Response(JSON.stringify({ detail }), { status });
  const narrator = { backend: "elevenlabs", voice: "JBFqnCBsd6RMkjVDRZzb" };
  try {
    globalThis.fetch = answer(402, {
      type: "payment_required",
      code: "insufficient_credits",
      message: "insufficient_credits message",
    });
    await assert.rejects(synthesize({ text: "Hi.", narrator, tools: {} }), {
      quota: true,
      vendor: "ElevenLabs",
      message: "ElevenLabs answered HTTP 402: insufficient_credits message",
    });
    globalThis.fetch = answer(401, {
      status: "quota_exceeded",
      message: "quota_exceeded message",
    });
    await assert.rejects(synthesize({ text: "Hi.", narrator, tools: {} }), {
      quota: true,
      message: "ElevenLabs answered HTTP 401: quota_exceeded message",
    });
    globalThis.fetch = answer(401, { code: "invalid_api_key" });
    await assert.rejects(synthesize({ text: "Hi.", narrator, tools: {} }), {
      quota: false,
    });
  } finally {
    globalThis.fetch = real;
  }
});

// Gemini answers spent prepaid credits with 402 and `error.status:
// "RESOURCE_EXHAUSTED"` (the live answer of 2026-10-16; Google's docs name the
// 402 but show no body), and a rate or daily limit with 429.
test("the real Gemini backend reads spent prepaid credits as a quota stop and a bare 402 as not one", async () => {
  const { synthesize } =
    await import("../../skills/explainer-video/scripts/lib/backend.mjs");
  const real = globalThis.fetch;
  const answer = (status, error) => async () =>
    new Response(JSON.stringify({ error }), { status });
  const narrator = { backend: "gemini", voice: "Kore", style: "warm" };
  try {
    globalThis.fetch = answer(402, {
      code: 402,
      status: "RESOURCE_EXHAUSTED",
      message: "Your prepayment credits are depleted.",
    });
    await assert.rejects(synthesize({ text: "Hi.", narrator, tools: {} }), {
      quota: true,
      vendor: "Gemini",
      message:
        "Gemini answered HTTP 402: Your prepayment credits are depleted.",
    });
    globalThis.fetch = answer(429, {
      code: 429,
      status: "RESOURCE_EXHAUSTED",
      message: "rate limit",
    });
    await assert.rejects(synthesize({ text: "Hi.", narrator, tools: {} }), {
      quota: true,
    });
    globalThis.fetch = answer(402, { code: 402, message: "no status" });
    await assert.rejects(synthesize({ text: "Hi.", narrator, tools: {} }), {
      quota: false,
    });
  } finally {
    globalThis.fetch = real;
  }
});
