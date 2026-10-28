// creative-video's setup: check the tool rows a run needs, and install the
// missing ones after the human's one yes. Tools go to the per-user tool cache,
// keyed by the lockfile's hash, fonts to the font store (ADR 0017), Kenney's
// sound packs to the sound store beside it.
//
//   node setup.mjs check [--voice <id>]    print the table; installs nothing
//   node setup.mjs install [--voice <id>]  the yes: install every missing row,
//                                          prune every stale install, print
//                                          the table again
//
// --voice names the narrator whose voice rows are listed (default: the English
// default narrator). A system package (ffmpeg) is never installed: its install
// lines (Linux, brew, winget) are printed for the human to run. Nor is a key
// (GEMINI_API_KEY, ELEVENLABS_API_KEY): it is checked with its vendor by a call
// that spends no TTS request or credits, and never stored or printed.
// stdout: the table (row, needed by, status, size, licence, writes to), the
//         install lines of each missing system package, where to get each key
//         not present, Gemini's data notice the first time a key is present,
//         one summary line
// writes: the key's fingerprint (a hash) to <config>/settings.json once its
//         data notice is shown
// exit:   0 every row present, nothing stale · 1 a row missing, refused or
//         failed, or an install stale · 2 usage, or a --voice id not in
//         narrators.json
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { formatSize, sha256 } from "./lib/files.mjs";
import { narrators } from "./lib/narrators.mjs";
import { userDirs } from "./lib/paths.mjs";
import {
  TOOL_DIRS,
  catalogue as readCatalogue,
  dest,
  fontGap,
  installFont,
  lockHash,
  loadBackend,
  ortBin,
  ortProvider,
  skill,
  staged,
} from "./lib/tools.mjs";
import { stage } from "./lib/stage.mjs";

const usage = "usage: node setup.mjs check|install [--voice <id>]";
stage("setup");
const [mode, ...flags] = process.argv.slice(2);
const voiceAt = flags.indexOf("--voice");
const voiceId = voiceAt < 0 ? undefined : flags.splice(voiceAt, 2)[1];
if (
  !["check", "install"].includes(mode) ||
  flags.length ||
  (voiceAt >= 0 && !voiceId)
) {
  console.error(usage);
  process.exit(2);
}
const narrator = narrators().find((n) =>
  voiceId ? n.id === voiceId : n.language === "en" && n.default,
);
if (!narrator) {
  console.error(`setup: no narrator ${voiceId}\n${usage}`);
  process.exit(2);
}

const backend = await loadBackend();
const dirs = userDirs();
const catalogue = readCatalogue();

// Every row without a `when`, and a `when: voice` row whose language and
// backend, where it names them, are the narrator's.
const forNarrator = (r) =>
  ["language", "backend"].every((k) => !(k in r) || r[k] === narrator[k]);
// The machine's compute capability, read when the catalogue holds a CUDA
// provider row, listed or not. The OS and CPU are what that row matches.
const cap = catalogue.some((r) => r.kind === "cuda")
  ? await backend.computeCapability()
  : null;
const machine = backend.platform();
// A CUDA provider row is listed only where its card can run it: no card, a
// failed probe or too old a card lists none, so such a machine downloads nothing.
const fitsCard = (r) =>
  r.kind !== "cuda" ||
  (machine.os === r.os && machine.arch === r.arch && cap >= r.minCapability);
const rows = catalogue.filter(
  (r) => fitsCard(r) && (!r.when || (r.when === "voice" && forNarrator(r))),
);

const STALE_MS = 30 * 24 * 60 * 60 * 1000;
// HyperFrames phones home and checks for updates unless told not to.
const quietEnv = {
  ...process.env,
  HYPERFRAMES_NO_TELEMETRY: "1",
  DO_NOT_TRACK: "1",
  HYPERFRAMES_NO_UPDATE_CHECK: "1",
};

// A model row's size is its files'.
const filesSize = (r) => r.files?.reduce((n, f) => n + f.size, 0);
const size = (r) => r.size ?? filesSize(r);
const stamp = (dir) => path.join(dir, ".stamp");
const du = (p) => {
  const s = fs.lstatSync(p);
  return s.isDirectory()
    ? fs.readdirSync(p).reduce((n, f) => n + du(path.join(p, f)), 0)
    : s.size;
};

// A key is present once its vendor takes it.
const CHECKS = { gemini: "geminiKey", elevenlabs: "elevenlabsKey" };
const keys = new Map();
for (const r of rows.filter((r) => r.kind === "key")) {
  const value = process.env[r.env];
  keys.set(
    r,
    value
      ? await backend[CHECKS[r.backend]](value, narrator.voice).then(
          (k) =>
            k.ok
              ? "present"
              : `refused: ${r.vendor} refused ${r.env} (${k.reason})`,
          (e) => `failed: ${e.message}`,
        )
      : "missing",
  );
}

// An install is present once its stamp is written, the last step of its install.
// Checking it touches the stamp, so an install a run still uses never goes stale.
function status(r) {
  if (r.kind === "key") return keys.get(r);
  if (r.kind === "system")
    return backend.which(r.command) ? "present" : "missing";
  if (r.kind === "font" && fontGap(r)) return "missing";
  // The provider lives in the npm folder: an npm install about to rebuild that
  // folder takes the libraries with it, so the row is missing until npm is there.
  if (
    r.kind === "cuda" &&
    !(
      fs.existsSync(stamp(dest({ kind: "npm" }))) &&
      ortProvider(dest({ kind: "npm" }))
    )
  )
    return "missing";
  const s = stamp(dest(r));
  if (!fs.existsSync(s)) return "missing";
  const now = new Date();
  fs.utimesSync(s, now, now);
  return "present";
}

// Installs in the tool cache that no catalogue row lands in on this machine
// (npm and Chrome under another lock hash, a model at another revision), whose
// stamp no run has touched in 30 days. Every catalogue row counts, listed or
// not, since only a listed row's check touches its stamp. One with no stamp
// never finished, and ages by its folder.
function stale() {
  const current = new Set([
    ...Object.values(TOOL_DIRS).map((f) => path.join(dirs.cache, f, lockHash)),
    ...catalogue.filter((r) => r.kind === "model").map((r) => dest(r)),
  ]);
  const out = [];
  for (const folder of [...Object.values(TOOL_DIRS), "models"]) {
    const base = path.join(dirs.cache, folder);
    for (const name of fs.existsSync(base) ? fs.readdirSync(base).sort() : []) {
      const dir = path.join(base, name);
      const st =
        fs.statSync(stamp(dir), { throwIfNoEntry: false }) ?? fs.statSync(dir);
      const age = Date.now() - st.mtimeMs;
      if (!current.has(dir) && age > STALE_MS)
        out.push({
          id: `stale ${folder}/${name}`,
          dir,
          days: Math.floor(age / 864e5),
          size: du(dir),
        });
    }
  }
  return out;
}

// A row's files from Hugging Face into `dir`, pinned by revision and checked by
// sha256, as ADR 0017 hosts models.
async function fetchFiles(r, dir) {
  for (const f of r.files) {
    const file = path.join(dir, ...f.path.split("/"));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    await backend.download(
      `https://huggingface.co/${r.repo}/resolve/${r.revision}/${f.path}`,
      file,
    );
    const sum = await sha256(file);
    if (sum !== f.sha256)
      throw new Error(`${f.path} has sha256 ${sum}, pinned ${f.sha256}`);
  }
}

// Each Kenney pack's zip, checked by sha256, unpacked into `dir/<pack>`.
async function fetchPacks(r, dir) {
  for (const p of r.packs) {
    const zip = path.join(dir, `${p.name}.zip`);
    await backend.download(p.url, zip);
    const sum = await sha256(zip);
    if (sum !== p.sha256)
      throw new Error(`${p.name}.zip has sha256 ${sum}, pinned ${p.sha256}`);
    await backend.unzipSounds(zip, path.join(dir, p.name));
    fs.rmSync(zip);
  }
}

async function install(r) {
  if (r.kind === "font") return installFont(r, backend);
  const dir = dest(r);
  // A missing row's folder can hold what an earlier install left half done.
  // A model is written beside it and renamed in, so it never is.
  if (r.kind !== "model") {
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
  }
  if (r.kind === "npm") {
    for (const f of ["package.json", "package-lock.json"])
      fs.copyFileSync(path.join(skill, f), path.join(dir, f));
    // onnxruntime-node's postinstall otherwise fetches its CUDA provider from
    // NuGet on Linux x64 (1.30.0): a download only the onnx-cuda row makes.
    const code = await backend.npmCi(dir, {
      ...quietEnv,
      ONNXRUNTIME_NODE_INSTALL: "skip",
    });
    if (code !== 0) throw new Error(`npm ci exited ${code}`);
  } else if (r.kind === "chrome") {
    const nodeDir = dest({ kind: "npm" });
    if (!fs.existsSync(stamp(nodeDir)))
      throw new Error("needs npm-packages first");
    const code = await backend.ensureChrome(nodeDir, dir, quietEnv);
    if (code !== 0)
      throw new Error(`hyperframes browser ensure exited ${code}`);
  } else if (r.kind === "cuda") {
    const nodeDir = dest({ kind: "npm" });
    if (!fs.existsSync(stamp(nodeDir)))
      throw new Error("needs npm-packages first");
    const nupkg = path.join(dir, "provider.nupkg");
    await backend.download(r.url, nupkg);
    const sum = await sha256(nupkg);
    if (sum !== r.sha256)
      throw new Error(`the package has sha256 ${sum}, pinned ${r.sha256}`);
    await backend.extractOrtCuda(nupkg, ortBin(nodeDir));
    fs.rmSync(nupkg);
  } else if (r.kind === "model") {
    await staged(dir, (part) => fetchFiles(r, part));
  } else if (r.kind === "sounds") {
    // The zips unpack with the npm install's JSZip.
    if (!fs.existsSync(stamp(dest({ kind: "npm" }))))
      throw new Error("needs npm-packages first");
    await staged(dir, (part) => fetchPacks(r, part));
  }
  fs.writeFileSync(stamp(dir), "");
  return "present";
}

// Whether a key's data notice is due, recording that it was shown. No tier
// can be read from a key, so every key sees it once, remembered by a
// fingerprint: never the key itself.
function firstNotice(key) {
  const file = path.join(dirs.config, "settings.json");
  const settings = fs.existsSync(file)
    ? JSON.parse(fs.readFileSync(file, "utf8"))
    : {};
  const fingerprint = crypto
    .createHash("sha256")
    .update(key)
    .digest("hex")
    .slice(0, 16);
  if (settings.geminiNotice?.includes(fingerprint)) return false;
  settings.geminiNotice = [...(settings.geminiNotice ?? []), fingerprint];
  fs.mkdirSync(dirs.config, { recursive: true });
  fs.writeFileSync(file, JSON.stringify(settings, null, 2) + "\n");
  return true;
}

// What the CUDA provider row says about the host: whether the provider loads
// here, probed once the row is present, since a missing CUDA 13 or cuDNN 9
// library shows only by running.
async function cudaLines(state) {
  const r = rows.find((r) => r.kind === "cuda");
  if (!r || state.get(r) !== "present") return [];
  const why = await backend.cudaProbe(dest({ kind: "npm" }));
  // The row's install lines are cuDNN's: other missing libraries get none.
  const cudnn = why?.includes("libcudnn");
  return why
    ? [
        "",
        `${r.id}: CUDA is unavailable here: ${why}. Kokoro stays on the CPU. Install the NVIDIA libraries yourself, then check again${cudnn ? "; for cuDNN 9:" : "."}`,
        ...(cudnn
          ? Object.entries(r.install).map(([via, line]) => `  ${via}: ${line}`)
          : []),
      ]
    : [
        "",
        `${r.id}: Kokoro runs on the GPU here (the CUDA provider loads, compute capability ${cap.toFixed(1)}).`,
      ];
}

function report(state, staleInstalls, cudaNote) {
  const lines = [
    "| row | needed by | status | size | licence | writes to |",
    "| --- | --- | --- | --- | --- | --- |",
  ];
  for (const r of rows) {
    const where =
      r.kind === "system"
        ? "system, you install it"
        : r.kind === "key"
          ? `nothing, you set ${r.env}`
          : dest(r);
    lines.push(
      `| ${r.id} | ${r.neededBy} | ${state.get(r)} | ${size(r) ? formatSize(size(r)) : "-"} | ${r.licence} | ${where} |`,
    );
  }
  for (const s of staleInstalls)
    lines.push(
      `| ${s.id} | nothing | stale, unused ${s.days} days | ${formatSize(s.size)} | - | ${s.dir} |`,
    );
  lines.push(...cudaNote);
  for (const r of rows.filter(
    (r) => r.kind === "system" && state.get(r) !== "present",
  )) {
    lines.push(
      "",
      `${r.id} is a system package; install it yourself, then check again:`,
    );
    for (const [via, line] of Object.entries(r.install))
      lines.push(`  ${via}: ${line}`);
  }
  for (const r of rows.filter((r) => r.kind === "key")) {
    if (state.get(r) !== "present")
      lines.push(
        "",
        `${r.id} is a key you set yourself: get a free one at ${r.get}, then set ${r.env} and check again.`,
      );
    else if (r.backend === "gemini" && firstNotice(process.env[r.env]))
      lines.push(
        "",
        "Gemini data notice (shown once for this key): narration text goes to Google to be voiced. On the free tier Google may use it and the audio to improve its products, and people may review them; a paid key's data is not used that way.",
      );
  }
  const missing = rows.filter((r) => state.get(r) !== "present");
  const parts = [];
  // A system package has no size: setup installs none of them, nor a refused row.
  const total = missing
    .filter((r) => !state.get(r).startsWith("refused"))
    .reduce((n, r) => n + (size(r) || 0), 0);
  if (missing.length)
    parts.push(
      `not present: ${missing.map((r) => r.id).join(", ")}${total ? ` (${formatSize(total)} to install)` : ""}`,
    );
  if (staleInstalls.length)
    parts.push(
      `stale: ${staleInstalls.length} install(s), ${formatSize(staleInstalls.reduce((n, s) => n + s.size, 0))} to free`,
    );
  lines.push("", parts.length ? parts.join("; ") : "ready: every row present");
  console.log(lines.join("\n"));
  return parts.length ? 1 : 0;
}

const state = new Map(rows.map((r) => [r, status(r)]));
if (mode === "install") {
  for (const r of rows) {
    if (state.get(r) !== "missing" || ["system", "key"].includes(r.kind))
      continue;
    try {
      state.set(r, await install(r));
    } catch (e) {
      state.set(r, `failed: ${e.message}`);
    }
  }
  for (const s of stale()) fs.rmSync(s.dir, { recursive: true, force: true });
}
process.exit(report(state, stale(), await cudaLines(state)));
