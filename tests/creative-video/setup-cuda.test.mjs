// The setup stage through its process door, part 4: the CUDA provider row
// Kokoro's voice runs on where the card can run it.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  FAKE_SHA,
  cacheDir,
  calls,
  fixture,
  machine,
  on,
  realRows,
  row,
  run,
} from "./setup-lib.mjs";
import { ORT_CUDA_MIN_CAP } from "../../skills/creative-video/scripts/lib/tools.mjs";

const ID = "onnx-cuda";
const cudaFixture = () =>
  fixture(
    realRows().map((r) => (r.kind === "cuda" ? { ...r, sha256: FAKE_SHA } : r)),
  );

test("a card of compute capability 7.5 on Linux x64 lists the CUDA provider row after npm-packages, with its size and licence", () => {
  const r = run(cudaFixture(), ["check"], "ffmpeg", machine(7.5));
  const cells = row(r.out, ID);
  assert.equal(cells[1], "voice (Kokoro on the GPU)");
  assert.equal(cells[2], "missing");
  assert.equal(cells[3], "236 MB");
  assert.match(cells[4], /MIT/);
  assert.ok(r.out.indexOf(`| ${ID} |`) > r.out.indexOf("| npm-packages |"));
});

test("no row, no download and today's npm install where the machine cannot run it", () => {
  const cases = {
    "no card": machine(null),
    "a card under 7.5": machine(7.0),
    "a failed probe": { CREATIVE_VIDEO_FAKE_GPU: "failed" },
    macOS: on("darwin/arm64/15.0", machine(8.6)),
    Windows: on("win32/x64", machine(8.6)),
  };
  for (const [what, env] of Object.entries(cases)) {
    const fx = cudaFixture();
    const i = run(fx, ["install"], "ffmpeg", env);
    assert.equal(i.code, 0, `${what}: ${i.out}${i.err}`);
    assert.equal(row(i.out, ID), undefined, `${what}: ${i.out}`);
    assert.equal(
      calls(fx).filter((c) => /nupkg|extractOrtCuda/.test(JSON.stringify(c)))
        .length,
      0,
      `${what} downloaded the provider`,
    );
    const ci = calls(fx).filter((c) => c.call === "npmCi");
    assert.deepEqual(
      ci.map((c) => c.onnxruntime),
      ["skip"],
    );
  }
});

test("a narrator that is not Kokoro lists no CUDA row", () => {
  const r = run(
    cudaFixture(),
    ["check", "--voice", "ar-eg-csagent-2"],
    "ffmpeg",
    machine(7.5),
  );
  assert.equal(row(r.out, ID), undefined, r.out);
});

test("install downloads the pinned package after npm-packages, puts the provider in onnxruntime-node's folder, and a second check is present", () => {
  const fx = cudaFixture();
  const i = run(fx, ["install"], "ffmpeg", machine(7.5));
  assert.equal(i.code, 0, i.out + i.err);
  const log = calls(fx);
  const dl = log.findIndex((c) => /nupkg/.test(c.url ?? ""));
  assert.ok(dl > log.findIndex((c) => c.call === "npmCi"), "after npm ci");
  assert.match(
    log[dl].url,
    /microsoft\.ml\.onnxruntime\.gpu\.linux\/1\.30\.0\//,
  );
  const node = path.join(cacheDir(fx), "node");
  const [lock] = fs.readdirSync(node);
  for (const f of [
    "libonnxruntime_providers_cuda.so",
    "libonnxruntime_providers_shared.so",
  ])
    assert.ok(
      fs.existsSync(
        path.join(
          node,
          lock,
          "node_modules/onnxruntime-node/bin/napi-v6/linux/x64",
          f,
        ),
      ),
      f,
    );
  const c = run(fx, ["check"], "ffmpeg", machine(7.5));
  assert.equal(row(c.out, ID)[2], "present", c.out);
  // The stamp lives apart from the libraries: a rebuilt npm folder keeps it.
  fs.rmSync(
    path.join(
      node,
      lock,
      "node_modules/onnxruntime-node/bin/napi-v6/linux/x64/libonnxruntime_providers_cuda.so",
    ),
  );
  const gone = run(fx, ["check"], "ffmpeg", machine(7.5));
  assert.equal(row(gone.out, ID)[2], "missing", gone.out);
});

test("an npm folder about to be rebuilt takes the provider with it, so the row reads missing until npm is back", () => {
  const fx = cudaFixture();
  run(fx, ["install"], "ffmpeg", machine(7.5));
  const node = path.join(cacheDir(fx), "node");
  const [lock] = fs.readdirSync(node);
  fs.rmSync(path.join(node, lock, ".stamp"));
  const c = run(fx, ["check"], "ffmpeg", machine(7.5));
  assert.equal(row(c.out, ID)[2], "missing", c.out);
  const i = run(fx, ["install"], "ffmpeg", machine(7.5));
  assert.equal(row(i.out, ID)[2], "present", i.out);
});

test("a package whose sha256 differs from its pin fails the row and installs no provider", () => {
  const fx = fixture(
    realRows().map((r) =>
      r.kind === "cuda" ? { ...r, sha256: "0".repeat(64) } : r,
    ),
  );
  const i = run(fx, ["install"], "ffmpeg", machine(7.5));
  assert.match(row(i.out, ID)[2], /^failed: .*sha256/, i.out);
  assert.equal(calls(fx).filter((c) => c.call === "extractOrtCuda").length, 0);
});

test("with the provider loading, setup says Kokoro runs on the GPU", () => {
  const fx = cudaFixture();
  const i = run(fx, ["install"], "ffmpeg", machine(7.5));
  assert.match(i.out, /^onnx-cuda: Kokoro runs on the GPU here/m, i.out);
});

test("with a library missing, setup names it, prints the install line and keeps Kokoro on the CPU", () => {
  const fx = cudaFixture();
  const env = { ...machine(7.5), CREATIVE_VIDEO_FAKE_CUDA: "libcudnn.so.9" };
  const i = run(fx, ["install"], "ffmpeg", env);
  assert.equal(i.code, 0, i.out + i.err);
  assert.match(i.out, /^onnx-cuda: CUDA is unavailable here: libcudnn\.so\.9/m);
  assert.match(i.out, /Kokoro stays on the CPU/);
  assert.match(i.out, /apt: sudo apt install cudnn9-cuda-13/);
  assert.doesNotMatch(i.out, /runs on the GPU here/);
});

test("a missing library other than cuDNN is named without the cuDNN install line", () => {
  const fx = cudaFixture();
  const env = {
    ...machine(7.5),
    CREATIVE_VIDEO_FAKE_CUDA:
      "libcudart.so.13 is not found by the dynamic loader",
  };
  const i = run(fx, ["install"], "ffmpeg", env);
  assert.match(i.out, /CUDA is unavailable here: libcudart\.so\.13/);
  assert.doesNotMatch(i.out, /apt:|cudnn9/);
});

test("the row's compute capability floor is the one the voice stage checks", () => {
  const cuda = realRows().find((r) => r.id === ID);
  assert.equal(cuda.minCapability, ORT_CUDA_MIN_CAP);
});
