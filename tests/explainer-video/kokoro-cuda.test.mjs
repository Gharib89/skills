// The Kokoro adapter's device choice, driven through `synthesize()` over a stub
// tool cache whose `kokoro-js` records the device each load asked for and whose
// `onnxruntime-node` answers the CUDA probe (run in a child process, so it reads
// its verdict from the environment). Each case imports a fresh copy of the
// adapter, which keeps the loaded model in module state; a stub `nvidia-smi` on
// PATH stands in for the card.
import { after, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const temps = [];
after(() =>
  temps.forEach((t) => fs.rmSync(t, { recursive: true, force: true })),
);
const tmp = (name) => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), `${name}-`));
  temps.push(d);
  return d;
};

// A tool cache; with `provider`, onnxruntime-node's folder holds the CUDA
// provider setup installs there.
function toolCache({ provider }) {
  const node = tmp("kokoro-cuda");
  const stub = (name, body) => {
    fs.mkdirSync(path.join(node, "node_modules", name), { recursive: true });
    fs.writeFileSync(path.join(node, "node_modules", name, "index.js"), body);
  };
  fs.writeFileSync(path.join(node, "package.json"), "{}");
  stub("@huggingface/transformers", "exports.env = {};");
  stub("phonemizer", "exports.phonemize = async (s) => [s];");
  stub(
    "onnxruntime-node",
    `exports.Tensor = class {};
    exports.InferenceSession = { create: async () => {
      globalThis.probes = (globalThis.probes ?? 0) + 1;
      if (process.env.PROBE_FAIL) throw new Error(process.env.PROBE_FAIL);
      return { run: async () => ({}) };
    } };`,
  );
  stub(
    "kokoro-js",
    `exports.KokoroTTS = { from_pretrained: async (model, o) => {
      globalThis.kokoroLoads.push(o.device);
      return { generate: async (text) => {
        if (o.device === "cuda" && globalThis.kokoroFail)
          throw new Error("CUDA out of memory");
        return { audio: new Float32Array(text.length) };
      } };
    } };`,
  );
  if (provider) {
    const bin = path.join(
      node,
      "node_modules/onnxruntime-node/bin/napi-v6/linux/x64",
    );
    fs.mkdirSync(bin, { recursive: true });
    for (const f of [
      "libonnxruntime_providers_cuda.so",
      "libonnxruntime_providers_shared.so",
    ])
      fs.writeFileSync(path.join(bin, f), "");
  }
  return { node, models: { "model:kokoro-82m": node } };
}

// A PATH holding an `nvidia-smi` that answers `cap`, or none with no card.
function withCard(cap) {
  const dir = tmp("nvidia-smi");
  if (cap) {
    const smi = path.join(dir, "nvidia-smi");
    fs.writeFileSync(smi, `#!/bin/sh\necho ${cap}\n`, { mode: 0o755 });
  }
  return dir;
}

let n = 0;
async function voice({
  provider = true,
  cap = "7.5",
  probeFail,
  generateFail,
} = {}) {
  const tools = toolCache({ provider });
  globalThis.kokoroLoads = [];
  globalThis.kokoroFail = generateFail;
  const env = { ...process.env };
  process.env.PATH = withCard(cap);
  if (probeFail) process.env.PROBE_FAIL = probeFail;
  const errors = [];
  const error = console.error;
  console.error = (...a) => errors.push(a.join(" "));
  try {
    const { synthesize } = await import(
      `../../skills/explainer-video/scripts/lib/backend/voice.mjs?case=${n++}`
    );
    const { samples } = await synthesize({
      text: "Hello there.",
      narrator: { backend: "kokoro", voice: "bf_emma" },
      tools,
    });
    return { loads: globalThis.kokoroLoads, errors, samples };
  } finally {
    console.error = error;
    process.env.PATH = env.PATH;
    delete process.env.PROBE_FAIL;
  }
}

test("a card of compute capability 7.5, the CUDA provider installed and its libraries loading voices on CUDA", async () => {
  const r = await voice();
  assert.deepEqual(r.loads, ["cuda"]);
  assert.deepEqual(r.errors, []);
});

test("a failing CUDA probe loads Kokoro on the CPU with one stderr line naming the library", async () => {
  const r = await voice({
    probeFail: "libcudnn.so.9: cannot open shared object file",
  });
  assert.deepEqual(r.loads, ["cpu"]);
  assert.equal(r.errors.length, 1, r.errors.join("\n"));
  assert.match(r.errors[0], /libcudnn\.so\.9/);
  assert.equal(r.samples.length, "Hello there.".length);
});

test("without the provider, without a card or under 7.5, Kokoro loads on the CPU without probing", async () => {
  const fails = { probeFail: "probe ran" };
  for (const opts of [{ provider: false }, { cap: null }, { cap: "7.0" }]) {
    const r = await voice({ ...fails, ...opts });
    assert.deepEqual(r.loads, ["cpu"], JSON.stringify(opts));
    assert.deepEqual(r.errors, [], JSON.stringify(opts));
  }
});

test("a call that throws on CUDA reloads Kokoro on the CPU once, with one stderr line, and returns its audio", async () => {
  const r = await voice({ generateFail: true });
  assert.deepEqual(r.loads, ["cuda", "cpu"]);
  assert.equal(r.errors.length, 1, r.errors.join("\n"));
  assert.match(r.errors[0], /CUDA out of memory/);
  assert.equal(r.samples.length, "Hello there.".length);
});
