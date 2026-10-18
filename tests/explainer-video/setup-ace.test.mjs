// The setup stage through its process door, part 2: the ACE-Step row, its CPU
// and GPU paths, pins and the macOS platform floors.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {
  CPU_PIN,
  aceDirs,
  aceRow,
  cacheDir,
  calls,
  cpuFixture,
  enrolled,
  fixture,
  here,
  machine,
  on,
  pyRows,
  realRows,
  row,
  run,
  source,
} from "./setup-lib.mjs";

test("ace-step is listed only when asked, and on a card under compute capability 8.0 it shows the CPU path's cost per 30 s of score", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow()]);
  const plain = run(fx, ["check"], "ffmpeg,uv", machine(7.5));
  assert.equal(row(plain.out, "ace-step"), undefined, plain.out);
  assert.doesNotMatch(plain.out, /per 30 s of score/);
  const all = run(fx, ["check", "--all"], "ffmpeg,uv", machine(7.5));
  assert.equal(all.code, 1, all.out + all.err);
  assert.equal(row(all.out, "ace-step")[2], "missing");
  assert.equal(row(all.out, "ace-step")[3], "10.8 GB");
  assert.match(
    all.out,
    /^ace-step runs on the CPU here \(compute capability 7\.5, under 8\.0: no bfloat16, and float16 gives NaN\): about 1 min 28 s and 15\.0 GB RAM per 30 s of score\.$/m,
  );
  assert.deepEqual(calls(fx), []);
});

test("ace-step runs on the GPU from compute capability 8.0, and on the CPU with no NVIDIA card", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow()]);
  const ampere = run(fx, ["check", "--all"], "ffmpeg,uv", machine(8.6, 4e9));
  assert.equal(
    row(ampere.out, "ace-step")[2],
    "missing",
    "a GPU run is not held to the CPU's RAM",
  );
  assert.match(
    ampere.out,
    /^ace-step runs on the GPU here \(compute capability 8\.6\)\.$/m,
  );
  assert.doesNotMatch(ampere.out, /per 30 s of score/);
  assert.match(
    run(fx, ["check", "--all"], "ffmpeg,uv", machine(8.0)).out,
    /^ace-step runs on the GPU here \(compute capability 8\.0\)\.$/m,
  );
  const none = run(fx, ["check", "--all"], "ffmpeg,uv", machine(null));
  assert.match(
    none.out,
    /^ace-step runs on the CPU here \(no NVIDIA card\): about 1 min 28 s/m,
  );
});

test("a machine short of the CPU path's RAM is refused before any download", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow()]);
  const r = run(fx, ["install", "--all"], "ffmpeg,uv", machine(7.5, 8e9));
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(
    row(r.out, "ace-step")[2],
    "refused: the CPU path needs 15.0 GB RAM, this machine has 8.0 GB",
  );
  assert.doesNotMatch(r.out, /to install/, "a refused row is not installed");
  assert.deepEqual(calls(fx), []);
  assert.ok(!fs.existsSync(path.join(cacheDir(fx), "python")));
});

test("ace-step without uv is refused before any download", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow()]);
  const r = run(fx, ["install", "--all"], "ffmpeg", machine(7.5));
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(row(r.out, "uv")[2], "missing");
  assert.equal(
    row(r.out, "ace-step")[2],
    "refused: install uv first, then check again",
  );
  assert.doesNotMatch(r.out, /to install/, "a refused row is not installed");
  assert.deepEqual(calls(fx), []);
  assert.ok(!fs.existsSync(path.join(cacheDir(fx), "python")));
});

test("ace-step installs its code at the pinned commit, syncs it under uv from its own lock, and fetches its checkpoints at their pinned revision", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow()]);
  const r = run(fx, ["install", "--all"], "ffmpeg,uv", machine(7.5));
  assert.equal(r.code, 0, r.out + r.err);
  const where = path.join(cacheDir(fx), "python", "ace-step@fedcba9-0123456");
  assert.equal(row(r.out, "ace-step")[5], where);
  assert.deepEqual(
    calls(fx).map((c) => c.url ?? c.call),
    [
      "https://codeload.github.com/org/ace/zip/fedcba9876543210fedcba9876543210fedcba98",
      "extract",
      "uvSync",
      "https://huggingface.co/org/ace-weights/resolve/0123456789abcdef0123456789abcdef01234567/dit/model.safetensors",
      "https://huggingface.co/org/ace-weights/resolve/0123456789abcdef0123456789abcdef01234567/vae/config.json",
    ],
  );
  const sync = calls(fx).find((c) => c.call === "uvSync");
  assert.equal(sync.dir, path.join(where, "src"));
  assert.ok(fs.existsSync(path.join(where, "src", "pyproject.toml")));
  assert.ok(
    fs.existsSync(path.join(where, "checkpoints", "dit", "model.safetensors")),
  );
  assert.ok(!fs.existsSync(path.join(where, "source.zip")));
  assert.equal(
    row(
      run(fx, ["check", "--all"], "ffmpeg,uv", machine(7.5)).out,
      "ace-step",
    )[2],
    "present",
  );
});

test("on the CPU path ace-step syncs the CPU pin, not the upstream lock, into its own folder, sized by the CPU env", () => {
  const fx = cpuFixture();
  const check = run(fx, ["check", "--all"], "ffmpeg,uv", machine(7.5));
  assert.equal(row(check.out, "ace-step")[3], "5.8 GB");
  assert.match(check.out, /\(5\.8 GB to install\)$/m);
  const r = run(fx, ["install", "--all"], "ffmpeg,uv", machine(7.5));
  assert.equal(r.code, 0, r.out + r.err);
  const [dir] = aceDirs(fx);
  assert.match(dir, /^ace-step@fedcba9-0123456-cpu[0-9a-f]{7}$/);
  assert.equal(
    row(r.out, "ace-step")[5],
    path.join(cacheDir(fx), "python", dir),
  );
  const src = path.join(cacheDir(fx), "python", dir, "src");
  assert.equal(
    fs.readFileSync(path.join(src, "pyproject.toml"), "utf8"),
    CPU_PIN.pyproject,
  );
  assert.equal(
    fs.readFileSync(path.join(src, "uv.lock"), "utf8"),
    CPU_PIN.lock,
  );
  assert.equal(calls(fx).find((c) => c.call === "uvSync").dir, src);
});

test("on the GPU path ace-step keeps the upstream lock and its folder, and a CPU env is not its env", () => {
  const fx = cpuFixture();
  assert.equal(
    row(
      run(fx, ["check", "--all"], "ffmpeg,uv", machine(8.6)).out,
      "ace-step",
    )[3],
    "10.8 GB",
  );
  assert.equal(
    run(fx, ["install", "--all"], "ffmpeg,uv", machine(7.5)).code,
    0,
  );
  assert.equal(
    row(
      run(fx, ["check", "--all"], "ffmpeg,uv", machine(8.6)).out,
      "ace-step",
    )[2],
    "missing",
  );
  const gpu = run(fx, ["install", "--all"], "ffmpeg,uv", machine(8.6));
  assert.equal(gpu.code, 0, gpu.out + gpu.err);
  const dir = aceDirs(fx).find((d) => !d.includes("-cpu"));
  assert.equal(dir, "ace-step@fedcba9-0123456");
  const src = path.join(cacheDir(fx), "python", dir, "src");
  assert.equal(
    fs.readFileSync(path.join(src, "pyproject.toml"), "utf8"),
    "[project]\n",
  );
  assert.ok(!fs.existsSync(path.join(src, "uv.lock")));
});

test("the carried CPU pin was derived from the ACE-Step commit the row pins, so a bump of that pin fails until the pin is re-derived", () => {
  const ace = JSON.parse(
    fs.readFileSync(path.join(source, "setup", "rows.json"), "utf8"),
  ).rows.find((r) => r.id === "ace-step");
  assert.equal(ace.cpu.env.derivedFrom, ace.source.revision);
});

test("the carried CPU pin names only +cpu torch builds, none depending on an NVIDIA package, triton or a CUDA build, and its pyproject names no CUDA index", () => {
  const rows = JSON.parse(
    fs.readFileSync(path.join(source, "setup", "rows.json"), "utf8"),
  ).rows;
  const { path: pin } = rows.find((r) => r.id === "ace-step").cpu.env;
  const lock = fs.readFileSync(path.join(source, pin, "uv.lock"), "utf8");
  const project = fs.readFileSync(
    path.join(source, pin, "pyproject.toml"),
    "utf8",
  );
  // Optional flash-attn wheels and PyPI's torch fork stay in the lock but no
  // sync installs them: the +cpu torch builds are what Linux and Windows take.
  const blocks = lock
    .split("[[package]]")
    .filter((b) => /name = "torch(vision|audio)?"\nversion = "[^"]*\+/.test(b));
  assert.ok(blocks.length >= 3);
  for (const block of blocks) {
    assert.match(block, /\+cpu"/);
    assert.doesNotMatch(block, /nvidia|triton|\+cu\d/i);
  }
  assert.doesNotMatch(project, /\+cu\d|pytorch-cu/);
  assert.match(lock, /name = "torch"\nversion = "2\.10\.0\+cpu"/);
});

test("an ace-step checkpoint whose sha256 differs from its pin fails the row and leaves it missing", () => {
  const fx = fixture([...pyRows.slice(0, 2), aceRow("0".repeat(64))]);
  const r = run(fx, ["install", "--all"], "ffmpeg,uv", machine(7.5));
  assert.equal(r.code, 1, r.out + r.err);
  assert.match(
    row(r.out, "ace-step")[2],
    /^failed: dit\/model\.safetensors has sha256 [0-9a-f]{64}, pinned 0{64}/,
  );
  assert.match(r.out, /^not present: ace-step \(10\.8 GB to install\)$/m);
  assert.equal(
    row(
      run(fx, ["check", "--all"], "ffmpeg,uv", machine(7.5)).out,
      "ace-step",
    )[2],
    "missing",
  );
});

test("on Intel macOS ace-step is refused as unavailable, with the torch reason, and nothing of it is fetched or synced", () => {
  const fx = fixture(realRows());
  const check = run(fx, ["check", "--all"], "ffmpeg,uv", on("darwin/x64/14.5"));
  assert.equal(check.code, 1, check.out + check.err);
  assert.equal(
    row(check.out, "ace-step")[2],
    "refused: unavailable on darwin/x64 14.5: no torch 2.10 or torchcodec 0.10 wheel for Intel macOS; the last torch with an Intel macOS wheel is 2.2.2",
  );
  const install = run(
    fx,
    ["install", "--all"],
    "ffmpeg,uv",
    on("darwin/x64/14.5"),
  );
  assert.match(row(install.out, "ace-step")[2], /^refused: unavailable on/);
  const fetched = calls(fx).filter(
    (c) =>
      (c.call === "download" && /ace-step/i.test(c.url)) || c.call === "uvSync",
  );
  assert.deepEqual(fetched, []);
});

test("on Intel macOS an own voice's row is refused as unavailable, with the torch reason, before any sync", () => {
  const fx = fixture(realRows());
  enrolled(fx);
  const r = run(
    fx,
    ["install", "--voice", "own:maya"],
    "ffmpeg,uv",
    on("darwin/x64/14.5"),
  );
  assert.equal(r.code, 1, r.out + r.err);
  assert.equal(
    row(r.out, "own-voice")[2],
    "refused: unavailable on darwin/x64 14.5: no torch 2.6 wheel for Intel macOS; the last torch with an Intel macOS wheel is 2.2.2",
  );
  assert.deepEqual(
    calls(fx).filter(
      (c) =>
        c.call === "uvSync" ||
        (c.call === "download" && c.url.includes("chatterbox")),
    ),
    [],
  );
});

test("on Apple Silicon ace-step is refused below macOS 14 with the mlx reason, and offered from 14", () => {
  const fx = fixture(realRows());
  const old = run(fx, ["check", "--all"], "ffmpeg,uv", on("darwin/arm64/13.6"));
  assert.equal(
    row(old.out, "ace-step")[2],
    "refused: unavailable on darwin/arm64 13.6: mlx 0.30.6 has wheels for macOS 14 and later only",
  );
  for (const v of ["14.0", "15.2"])
    assert.equal(
      row(
        run(fx, ["check", "--all"], "ffmpeg,uv", on(`darwin/arm64/${v}`)).out,
        "ace-step",
      )[2],
      "missing",
      v,
    );
  enrolled(fx);
  assert.equal(
    row(
      run(
        fx,
        ["check", "--voice", "own:maya"],
        "ffmpeg,uv",
        on("darwin/arm64/13.6"),
      ).out,
      "own-voice",
    )[2],
    "missing",
    "own voice resolves on Apple Silicon at macOS 13",
  );
});

test("on Linux and Windows x64 the torch rows are offered as before", () => {
  const fx = fixture(realRows());
  enrolled(fx);
  for (const p of ["linux/x64", "win32/x64"]) {
    assert.equal(
      row(run(fx, ["check", "--all"], "ffmpeg,uv", on(p)).out, "ace-step")[2],
      "missing",
      p,
    );
    assert.equal(
      row(
        run(fx, ["check", "--voice", "own:maya"], "ffmpeg,uv", on(p)).out,
        "own-voice",
      )[2],
      "missing",
      p,
    );
  }
});

test("ace-step's macOS 14 floor compares versions by their numbers, and an unknown version passes it", () => {
  const fx = fixture(realRows());
  const ace = (p) =>
    row(run(fx, ["check", "--all"], "ffmpeg,uv", on(p)).out, "ace-step")[2];
  for (const v of ["13.6.1", "9.9"])
    assert.equal(
      ace(`darwin/arm64/${v}`),
      `refused: unavailable on darwin/arm64 ${v}: mlx 0.30.6 has wheels for macOS 14 and later only`,
    );
  for (const p of ["darwin/arm64/14", "darwin/arm64/14.0.1", "darwin/arm64"])
    assert.equal(ace(p), "missing", p);
});
