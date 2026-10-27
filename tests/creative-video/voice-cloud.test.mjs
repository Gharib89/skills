// The voice stage through its process door, part 2: the Gemini and ElevenLabs
// narrators and their quota stops.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  SCENES,
  fixture,
  line,
  run,
  synths,
  voice,
  write,
} from "./voice-lib.mjs";

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
    /rate \d+(\.\d+)? chars\/s outside 7 to 18/,
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
  write(fx, AR_SCENES, "ar", { narrator: "bf_emma" });
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
    [["af_heart", undefined]],
  );
});

// The line as it read before #753: the new assertions must reject it.
const OLD_QUOTA_LINE =
  "voice: Gemini quota reached (Gemini answered HTTP 429: You exceeded your current quota); 1 scene(s) voiced before it are kept. Voice again once the quota resets (tomorrow, for a daily quota), which voices only the missing scenes; use a paid key; or choose another narrator in the brief";

test("a Gemini quota stop keeps the scenes voiced before it, and the next run voices only the rest", () => {
  const fx = fixture(AR_SCENES, "ar");
  assert.equal(run(fx, KEY).code, 0);
  const changed = structuredClone(AR_SCENES);
  changed[0].narration = [
    "شيب بياخد مهمة جديدة ويوصلها لحد pull request متراجع.",
  ];
  changed[2].narration = ["كل تغيير بيعدي على review قبل الـ merge."];
  write(fx, changed, "ar");
  const stopped = run(fx, { ...KEY, CREATIVE_VIDEO_FAKE_QUOTA: "2" });
  assert.equal(stopped.code, 1, stopped.out + stopped.err);
  const QUOTA_LINE =
    /^voice: Gemini quota reached \(Gemini answered HTTP 429: You exceeded your current quota\); 1 scene\(s\) voiced before it are kept\. Voice again once the quota resets \(tomorrow, for a daily quota\) or the credits are topped up, which voices only the missing scenes; set another key \(a paid one, for a free-tier limit\); or choose another narrator in the brief$/m;
  assert.match(stopped.err, QUOTA_LINE);
  assert.doesNotMatch(OLD_QUOTA_LINE, QUOTA_LINE);
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
  write(fx, SCENES, "en", { narrator: "elevenlabs-george" });

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
    CREATIVE_VIDEO_FAKE_QUOTA: "0",
  });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^voice: ElevenLabs quota reached \(ElevenLabs answered HTTP 401: This request exceeds your quota limit\); 0 scene\(s\) voiced before it are kept\./m,
  );
  assert.equal(synths(fx).length, 0);
});

test("a spent-credits quota stop offers topping up the credits", () => {
  const fx = fixture();
  ELEVEN(fx);
  const r = run(fx, {
    ELEVENLABS_API_KEY: "test-key",
    CREATIVE_VIDEO_FAKE_QUOTA: "0",
    CREATIVE_VIDEO_FAKE_CREDITS: "1",
  });
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    r.err,
    /^voice: ElevenLabs quota reached \(ElevenLabs answered HTTP 402: credits are depleted\); 0 scene\(s\) voiced before it are kept\. Voice again once the quota resets \(tomorrow, for a daily quota\) or the credits are topped up,/m,
  );
  assert.doesNotMatch(
    OLD_QUOTA_LINE.replace("Gemini", "ElevenLabs"),
    /or the credits are topped up/,
  );
});

// The real backend on a stubbed fetch: ElevenLabs answers spent credits with
// 402 and `detail.code: "insufficient_credits"`, and its legacy answer is 400 or
// 401 with `detail.status: "quota_exceeded"` (backend.mjs cites both docs), not
// 429.
test("the real ElevenLabs backend reads spent credits as a quota stop and invalid_api_key as not one", async () => {
  const { synthesize } =
    await import("../../skills/creative-video/scripts/lib/backend.mjs");
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
    await import("../../skills/creative-video/scripts/lib/backend.mjs");
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
    globalThis.fetch = async () =>
      new Response("Payment Required", { status: 402 });
    await assert.rejects(synthesize({ text: "Hi.", narrator, tools: {} }), {
      quota: false,
      message: "Gemini answered HTTP 402: Payment Required",
    });
  } finally {
    globalThis.fetch = real;
  }
});
