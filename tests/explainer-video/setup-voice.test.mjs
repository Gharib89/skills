// The setup stage through its process door, part 3: the Gemini, ElevenLabs and
// own-voice narrator rows.
import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import {
  calls,
  enrolled,
  fixture,
  here,
  machine,
  on,
  realRows,
  row,
  run,
  source,
} from "./setup-lib.mjs";

const AR = ["--voice", "ar-eg-csagent-2"];
const AR_MODEL = "model:egyptian-arabic-wav2vec2";
const ARABIC_FONTS = [
  "font:noto-naskh-arabic",
  "font:ibm-plex-sans-arabic",
  "font:noto-kufi-arabic",
];
const settings = (fx) =>
  path.join(fx.tmp, "config", "explainer-video", "settings.json");

test("check --voice for a Gemini narrator lists its key and the Arabic aligner, not the English voice rows", () => {
  const fx = fixture();
  const r = run(fx, ["check", ...AR]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.deepEqual(row(r.out, "key:gemini"), [
    "key:gemini",
    "voice (Gemini narrators)",
    "missing",
    "-",
    "Gemini API terms",
    "nothing, you set GEMINI_API_KEY",
  ]);
  assert.match(
    r.out,
    /^key:gemini is a key you set yourself: get a free one at https:\/\/aistudio\.google\.com\/apikey, then set GEMINI_API_KEY and check again\.$/m,
  );
  assert.equal(row(r.out, AR_MODEL)[2], "missing");
  assert.equal(row(r.out, AR_MODEL)[3], "317 MB");
  assert.ok(row(r.out, "npm-packages"));
  assert.equal(row(r.out, "model:kokoro-82m"), undefined, r.out);
  assert.equal(row(r.out, "model:wav2vec2-base-960h"), undefined, r.out);
  for (const font of ARABIC_FONTS)
    assert.equal(row(r.out, font)[2], "missing", r.out);
  assert.deepEqual(calls(fx), [], "no key, no call to Google");
});

test("an English-only check lists the Arabic font rows, which the style card's Arabic frame draws whatever the narrator", () => {
  const out = run(fixture(), ["check"]).out;
  for (const font of ARABIC_FONTS)
    assert.equal(row(out, font)?.[2], "missing", out);
});

test("a key Google refuses reads refused with Google's reason", () => {
  const fx = fixture();
  const r = run(fx, ["check", ...AR], "ffmpeg", { GEMINI_API_KEY: "bad-key" });
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(
    row(r.out, "key:gemini")[2],
    "refused: Google refused GEMINI_API_KEY (API_KEY_INVALID)",
  );
  assert.match(r.out, /^key:gemini is a key you set yourself/m);
  assert.doesNotMatch(r.out, /Gemini data notice/);
});

test("a key Google takes is present, spends no TTS request, and shows the data notice once for that key", () => {
  const fx = fixture();
  const key = { GEMINI_API_KEY: "good-key-123" };
  const first = run(fx, ["check", ...AR], "ffmpeg", key);
  assert.equal(row(first.out, "key:gemini")[2], "present");
  assert.doesNotMatch(first.out, /is a key you set yourself/);
  assert.deepEqual(calls(fx), [{ call: "geminiKey" }]);
  assert.match(
    first.out,
    /^Gemini data notice \(shown once for this key\): narration text goes to Google to be voiced\. On the free tier Google may use it and the audio to improve its products, and people may review them; a paid key's data is not used that way\.$/m,
  );
  const saved = fs.readFileSync(settings(fx), "utf8");
  assert.ok(!saved.includes(key.GEMINI_API_KEY), "the key was stored");
  assert.deepEqual(JSON.parse(saved).geminiNotice, [
    crypto
      .createHash("sha256")
      .update(key.GEMINI_API_KEY)
      .digest("hex")
      .slice(0, 16),
  ]);
  const second = run(fx, ["check", ...AR], "ffmpeg", key);
  assert.equal(row(second.out, "key:gemini")[2], "present");
  assert.doesNotMatch(second.out, /Gemini data notice/);
  const other = run(fx, ["check", ...AR], "ffmpeg", {
    GEMINI_API_KEY: "another-key",
  });
  assert.match(other.out, /Gemini data notice/);
  assert.equal(
    JSON.parse(fs.readFileSync(settings(fx))).geminiNotice.length,
    2,
  );
  assert.ok(calls(fx).every((c) => c.call === "geminiKey"));
});

test("a default check lists no Arabic or Gemini row", () => {
  const fx = fixture();
  const r = run(fx, ["check"], "ffmpeg", { GEMINI_API_KEY: "good-key-123" });
  assert.equal(row(r.out, AR_MODEL), undefined, r.out);
  assert.equal(row(r.out, "key:gemini"), undefined, r.out);
  assert.ok(row(r.out, "model:wav2vec2-base-960h"));
  assert.deepEqual(calls(fx), []);
  assert.ok(!fs.existsSync(settings(fx)));
});

test("install --voice for a Gemini narrator fetches the Arabic aligner at its pinned revision and installs no key", () => {
  const fx = fixture();
  const r = run(fx, ["install", ...AR]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(row(r.out, AR_MODEL)[2], "present");
  assert.equal(row(r.out, "key:gemini")[2], "missing");
  const base =
    "https://huggingface.co/agharib/egyptian-arabic-wav2vec2-xlsr-53-onnx/resolve/888b8be067d3a1ac2ca72806832f29e8786a3341";
  assert.deepEqual(
    calls(fx)
      .filter((c) => c.call === "download" && c.url.includes("huggingface"))
      .map((c) => c.url),
    [`${base}/vocab.json`, `${base}/onnx/model_int8.onnx`],
  );
  assert.match(r.out, /^not present: key:gemini$/m);
});

const EL = ["--voice", "elevenlabs-george"];

test("a default check and a check --all list no ElevenLabs key; check --voice elevenlabs-george lists it with where to get one, and the English aligner but not Kokoro", () => {
  const fx = fixture();
  for (const args of [["check"], ["check", "--all"]])
    assert.equal(row(run(fx, args).out, "key:elevenlabs"), undefined);
  const r = run(fx, ["check", ...EL]);
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(row(r.out, "key:elevenlabs")[2], "missing");
  assert.match(
    r.out,
    /^key:elevenlabs is a key you set yourself: get a free one at https:\/\/elevenlabs\.io\/app\/settings\/api-keys, then set ELEVENLABS_API_KEY and check again\.$/m,
  );
  assert.equal(row(r.out, "model:kokoro-82m"), undefined, r.out);
  assert.equal(row(r.out, "key:gemini"), undefined, r.out);
  assert.ok(row(r.out, "model:wav2vec2-base-960h"));
  assert.deepEqual(calls(fx), []);
});

test("an ElevenLabs key it refuses reads refused with its reason; one it takes is present, checked once, with no Gemini data notice", () => {
  const fx = fixture();
  const bad = run(fx, ["check", ...EL], "ffmpeg", {
    ELEVENLABS_API_KEY: "bad-key",
  });
  assert.equal(
    row(bad.out, "key:elevenlabs")[2],
    "refused: ElevenLabs refused ELEVENLABS_API_KEY (invalid_api_key)",
  );
  const good = run(fx, ["check", ...EL], "ffmpeg", {
    ELEVENLABS_API_KEY: "good-key-123",
  });
  assert.equal(row(good.out, "key:elevenlabs")[2], "present");
  assert.doesNotMatch(good.out, /Gemini data notice/);
  assert.deepEqual(
    calls(fx).map((c) => c.call),
    ["elevenlabsKey", "elevenlabsKey"],
  );
  // Each check reads the narrator's own voice.
  const george = JSON.parse(
    fs.readFileSync(path.join(source, "narrators.json"), "utf8"),
  ).narrators.find((n) => n.id === "elevenlabs-george").voice;
  assert.ok(calls(fx).every((c) => c.voice === george));
  assert.ok(!fs.existsSync(settings(fx)));
});

test("check --voice own:<name> lists the own-voice row, uv, Gemini's key and the Arabic aligner, with the CPU cost per 30 s of narration", () => {
  const fx = fixture(realRows());
  enrolled(fx);
  const r = run(
    fx,
    ["check", "--voice", "own:maya"],
    "ffmpeg,uv",
    machine(7.5),
  );
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(row(r.out, "own-voice")[2], "missing");
  assert.ok(row(r.out, "uv"));
  assert.equal(row(r.out, "key:gemini")[2], "missing");
  assert.equal(row(r.out, AR_MODEL)[2], "missing");
  assert.equal(row(r.out, "ace-step"), undefined);
  assert.equal(row(r.out, "model:kokoro-82m"), undefined);
  assert.match(
    r.out,
    /^own-voice runs on the CPU here \(compute capability 7\.5, under 8\.0\): about .* per 30 s of narration\.$/m,
  );
  assert.doesNotMatch(r.out, /per 30 s of score/);
});

test("install --voice own:<name> copies the skill's pyproject and lock, syncs them, and fetches the checkpoint at its pinned revision", () => {
  const fx = fixture(realRows());
  enrolled(fx);
  const r = run(
    fx,
    ["install", "--voice", "own:maya"],
    "ffmpeg,uv",
    machine(7.5),
  );
  const where = row(r.out, "own-voice")[5];
  assert.equal(row(r.out, "own-voice")[2], "present", r.out + r.err);
  const vc = path.join(fx.skill, "scripts", "voice", "vc");
  for (const f of ["pyproject.toml", "uv.lock"])
    assert.equal(
      fs.readFileSync(path.join(where, "src", f), "utf8"),
      fs.readFileSync(path.join(vc, f), "utf8"),
    );
  const urls = calls(fx)
    .filter((c) => c.call === "download")
    .map((c) => c.url);
  assert.ok(!urls.some((u) => u.includes("codeload")), urls.join());
  assert.ok(
    urls.includes(
      "https://huggingface.co/ResembleAI/chatterbox/resolve/5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18/s3gen.safetensors",
    ),
    urls.join(),
  );
  const sync = calls(fx).find((c) => c.call === "uvSync");
  assert.equal(sync.dir, path.join(where, "src"));
  assert.ok(
    fs.existsSync(path.join(where, "checkpoints", "s3gen.safetensors")),
  );
});

test("--voice own:<name> with nobody enrolled is a usage error", () => {
  const fx = fixture();
  const r = run(fx, ["check", "--voice", "own:nobody"]);
  assert.equal(r.code, 2, r.out + r.err);
  assert.match(r.err, /own:nobody/);
});

test("--voice with a narrator nobody ships is a usage error naming it", () => {
  const fx = fixture();
  const r = run(fx, ["check", "--voice", "nobody"]);
  assert.equal(r.code, 2, r.out + r.err);
  assert.match(r.err, /nobody/);
  assert.match(
    r.err,
    /^usage: node setup\.mjs check\|install \[--all\] \[--voice <id>\]$/m,
  );
  assert.deepEqual(calls(fx), []);
});
