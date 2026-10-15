// Everything setup and the stages reach outside the machine or the skill: npm,
// HyperFrames' Chrome download, the Fontsource API and CDN, Hugging Face, PATH,
// and the models. Callers load it through tools.mjs's loadBackend.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";

const win = process.platform === "win32";
// Children write to stderr, so stdout carries only setup's own table.
const quiet = ["ignore", 2, 2];

// The lock's only install scripts are esbuild's and onnxruntime-node's, and
// neither is needed: esbuild's binary arrives as an optional dependency, the
// onnxruntime CPU binding ships in its tarball. Ignoring them keeps npm 10 and
// npm 11 alike, and stops npm 11's unapproved-script warning, which agents
// misread as a step left to do.
export async function npmCi(dir, env) {
  // npm is npm.cmd on Windows, which spawn runs only through a shell.
  return (
    spawnSync("npm", ["ci", "--no-audit", "--no-fund", "--ignore-scripts"], {
      cwd: dir,
      env,
      stdio: quiet,
      shell: win,
    }).status ?? 1
  );
}

// HyperFrames downloads its pinned Chrome to `homedir()/.cache/hyperframes/chrome`
// (0.8.160) with no setting to move it, so `home` stands in for the home folder:
// HOME for Node on Linux and macOS, USERPROFILE on Windows.
export async function ensureChrome(nodeDir, home, env) {
  const childEnv = { ...env, HOME: home, USERPROFILE: home };
  delete childEnv.HYPERFRAMES_BROWSER_PATH;
  const cli = path.join(
    nodeDir,
    "node_modules",
    "hyperframes",
    "bin",
    "hyperframes.mjs",
  );
  return (
    spawnSync(process.execPath, [cli, "browser", "ensure"], {
      env: childEnv,
      stdio: quiet,
    }).status ?? 1
  );
}

export async function fontMeta(id) {
  const r = await fetch(
    `https://api.fontsource.org/v1/fonts/${encodeURIComponent(id)}`,
  );
  if (!r.ok)
    throw new Error(`Fontsource has no family ${id} (HTTP ${r.status})`);
  return r.json();
}

export async function download(url, file) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
}

export function which(cmd) {
  const exts = win
    ? (process.env.PATHEXT || ".EXE;.CMD;.BAT").split(";")
    : [""];
  for (const dir of (process.env.PATH || "").split(path.delimiter)) {
    for (const ext of exts) {
      const f = path.join(dir, cmd + ext);
      if (fs.statSync(f, { throwIfNoEntry: false })?.isFile()) return f;
    }
  }
  return null;
}

// The voice stage's models load from the tool cache, never the skill's folder:
// `tools.node` is the npm install, `tools.models` each model row's folder by id.
const fromCache = (nodeDir) =>
  createRequire(path.join(nodeDir, "package.json"));

// A narrator adapter: text in, audio out, never timings (ADR 0016). Kokoro
// reads one sentence per inference, so the whole text goes through its splitter.
let kokoro;
export async function synthesize({ text, narrator, tools }) {
  if (narrator.backend !== "kokoro")
    throw new Error(`no adapter for backend ${narrator.backend}`);
  const req = fromCache(tools.node);
  const { KokoroTTS, TextSplitterStream } = req("kokoro-js");
  if (!kokoro) {
    // kokoro-js's own dependency, pinned by the lock: requiring it from the same
    // install yields the instance kokoro-js reads its settings from.
    const { env } = req("@huggingface/transformers");
    env.allowRemoteModels = false;
    // An absolute path is read as a folder; a name under localModelPath must
    // pass the hub's model-id check, which the `@` in the cache name fails.
    kokoro = await KokoroTTS.from_pretrained(tools.models["model:kokoro-82m"], {
      dtype: "fp32",
      device: "cpu",
    });
  }
  // A plain string passed to stream() is never closed, so its last sentence
  // never yields (kokoro-js 1.2.1).
  const split = new TextSplitterStream();
  split.push(text);
  split.close();
  const parts = [];
  for await (const { audio } of kokoro.stream(split, { voice: narrator.voice }))
    parts.push(audio.audio);
  const samples = new Float32Array(parts.reduce((n, p) => n + p.length, 0));
  parts.reduce((o, p) => (samples.set(p, o), o + p.length), 0);
  return { samples, sampleRate: 24000 };
}

// One CTC model per language (ADR 0016).
const ALIGNERS = { en: "model:wav2vec2-base-960h" };

// A language's CTC model: its vocabulary, and its logits for 16 kHz audio,
// normalised as its feature extractor does.
export async function aligner({ language, tools }) {
  if (!ALIGNERS[language])
    throw new Error(`no aligner for language ${language}`);
  const dir = tools.models[ALIGNERS[language]];
  const ort = fromCache(tools.node)("onnxruntime-node");
  const session = await ort.InferenceSession.create(
    path.join(dir, "onnx", "model_int8.onnx"),
  );
  const vocab = JSON.parse(
    fs.readFileSync(path.join(dir, "vocab.json"), "utf8"),
  );
  async function logits(x) {
    let mean = 0;
    for (const v of x) mean += v;
    mean /= x.length;
    let sq = 0;
    for (const v of x) sq += (v - mean) ** 2;
    const sd = Math.sqrt(sq / x.length + 1e-7);
    const input = new ort.Tensor(
      "float32",
      x.map((v) => (v - mean) / sd),
      [1, x.length],
    );
    const out = (await session.run({ [session.inputNames[0]]: input }))[
      session.outputNames[0]
    ];
    return { data: out.data, frames: out.dims[1], classes: out.dims[2] };
  }
  return { vocab, logits };
}
