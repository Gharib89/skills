// The Kokoro adapter's call packing, driven through `synthesize()` over a stub
// tool cache: a `kokoro-js` whose generate() records each call's text and
// returns a sample per character, and a `phonemizer` that counts a character a
// token, so the budget reads in characters.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { synthesize } from "../../skills/creative-video/scripts/lib/backend.mjs";

const node = fs.mkdtempSync(path.join(os.tmpdir(), "kokoro-"));
after(() => fs.rmSync(node, { recursive: true, force: true }));
const stub = (name, body) => {
  fs.mkdirSync(path.join(node, "node_modules", name), { recursive: true });
  fs.writeFileSync(path.join(node, "node_modules", name, "index.js"), body);
};
fs.writeFileSync(path.join(node, "package.json"), "{}");
stub("@huggingface/transformers", "exports.env = {};");
stub("phonemizer", "exports.phonemize = async (s) => [s];");
stub(
  "kokoro-js",
  `exports.KokoroTTS = { from_pretrained: async () => ({
    generate: async (text) => {
      globalThis.kokoroCalls.push(text);
      return { audio: new Float32Array(text.length) };
    },
  }) };`,
);

const tools = { node, models: { "model:kokoro-82m": node } };
const narrator = { backend: "kokoro", voice: "bf_emma" };
const words = (n, w) => Array.from({ length: n }, () => w).join(" ");

async function calls(text) {
  globalThis.kokoroCalls = [];
  const { samples } = await synthesize({ text, narrator, tools });
  const got = globalThis.kokoroCalls;
  assert.equal(samples.length, got.join("").length);
  return got;
}

test("whole sentences pack into one Kokoro call while they fit the budget", async () => {
  const s = `${words(19, "word")}.`; // 95 characters
  assert.deepEqual(await calls(`${s} ${s} ${s}`), [`${s} ${s} ${s}`]);
});

test("a sentence that would pass the budget starts the next call", async () => {
  const s = `${words(29, "word")} end.`; // 149 characters
  const got = await calls(Array(5).fill(s).join(" "));
  assert.deepEqual(got, [`${s} ${s}`, `${s} ${s}`, s]);
});

test("a sentence over the budget breaks between words, every call within it", async () => {
  const s = `${words(120, "word")}.`; // 600 characters
  const got = await calls(s);
  assert.ok(got.length > 1, JSON.stringify(got));
  for (const c of got) assert.ok(c.length <= 400, `${c.length} characters`);
  assert.equal(got.join(" "), s);
});
