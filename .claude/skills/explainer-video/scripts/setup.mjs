// explainer-video's setup: check the tool rows a run needs, and install the
// missing ones after the human's one yes. Tools go to the per-user tool cache,
// keyed by the lockfile's hash, fonts to the font store (ADR 0017).
//
//   node setup.mjs check [--all] [--voice <id>]    print the table; installs
//                                                  nothing
//   node setup.mjs install [--all] [--voice <id>]  the yes: install every
//                                                  missing row, prune every
//                                                  stale install, print the
//                                                  table again
//
// --all adds the opt-in rows. --voice names the narrator whose voice rows are
// listed (default: the English default narrator). A system package (ffmpeg,
// uv) is never installed: its install lines (Linux, brew, winget) are printed
// for the human to run. Nor is a key (GEMINI_API_KEY, ELEVENLABS_API_KEY): it
// is checked with its vendor by a call that spends no TTS request or credits,
// and never stored or printed. `--voice own:<name>` names an enrolled own
// voice (voice/own-voice.mjs): its rows are Chatterbox's, Gemini's key and the
// Arabic aligner.
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
import {
  OWN_PREFIX,
  narrator as findNarrator,
  narrators,
} from "./lib/narrators.mjs";
import { userDirs } from "./lib/paths.mjs";
import { stores } from "./lib/style.mjs";
import {
  TOOL_DIRS,
  catalogue as readCatalogue,
  cpuEnv,
  dest,
  fontGap,
  installFont,
  lockHash,
  loadBackend,
  skill,
  staged,
  torchDevice,
  unavailable,
} from "./lib/tools.mjs";

const usage = "usage: node setup.mjs check|install [--all] [--voice <id>]";
const [mode, ...flags] = process.argv.slice(2);
const voiceAt = flags.indexOf("--voice");
const voiceId = voiceAt < 0 ? undefined : flags.splice(voiceAt, 2)[1];
if (
  !["check", "install"].includes(mode) ||
  flags.some((f) => f !== "--all") ||
  (voiceAt >= 0 && !voiceId)
) {
  console.error(usage);
  process.exit(2);
}
const all = flags.includes("--all");
const narrator = voiceId?.startsWith(OWN_PREFIX)
  ? findNarrator(voiceId, "ar")
  : narrators().find((n) =>
      voiceId ? n.id === voiceId : n.language === "en" && n.default,
    );
if (!narrator) {
  console.error(`setup: no narrator ${voiceId}\n${usage}`);
  process.exit(2);
}

const backend = await loadBackend();
const dirs = userDirs();
const catalogue = readCatalogue();

// Every row without a `when`; opt-in rows under --all; a `when: voice` row
// whose language and backend, where it names them, are the narrator's or its
// base narrator's (an own voice speaks through one); a `when: python` row (uv)
// only beside a row that runs Python.
const forNarrator = (r) =>
  ["language", "backend"].every(
    (k) => !(k in r) || r[k] === narrator[k] || r[k] === narrator.base?.[k],
  );
const rows = catalogue.filter(
  (r) =>
    !r.when ||
    (all && r.when === "opt-in") ||
    (r.when === "voice" && forNarrator(r)),
);
if (rows.some((r) => r.python))
  rows.push(...catalogue.filter((r) => r.when === "python"));

// The `fonts` rows saved style profiles carry (a draft fetched a family no row
// installs): every profile in the folders profiles are saved to (stores()) and
// each run's style.json under ./explainers, one row per family and version,
// none a catalogue row. A file that does not parse is a row of its own,
// refused.
const profileFiles = (explainers) => {
  const jsonIn = (d) =>
    fs.existsSync(d)
      ? fs
          .readdirSync(d)
          .filter((f) => f.endsWith(".json"))
          .map((f) => path.join(d, f))
      : [];
  return [
    ...stores(explainers, dirs).flatMap(jsonIn),
    ...(fs.existsSync(explainers)
      ? fs
          .readdirSync(explainers, { withFileTypes: true })
          .filter((e) => e.isDirectory())
          .map((e) => path.join(explainers, e.name, "style.json"))
          .filter((f) => fs.existsSync(f))
      : []),
  ];
};
const carried = new Map();
const unreadable = new Map();
for (const file of profileFiles(path.resolve("explainers"))) {
  try {
    const profile = JSON.parse(fs.readFileSync(file, "utf8"));
    for (const r of profile.fonts ?? [])
      if (!rows.some((c) => c.kind === "font" && c.family === r.family)) {
        // Drafts of one family each carry the weights they use: keep them all.
        const key = `${r.family}@${r.version}`;
        const files = [
          ...new Set([...(carried.get(key)?.files ?? []), ...r.files]),
        ];
        carried.set(key, { neededBy: "render", size: 0, ...r, files });
      }
  } catch (e) {
    // Bad JSON, or a shape the loop cannot read: one refused row, no crash.
    unreadable.set(file, e.message);
  }
}
rows.push(...carried.values());
for (const [file, why] of unreadable)
  rows.push({
    id: `profile:${path.relative(".", file)}`,
    kind: "profile",
    neededBy: "render",
    licence: "-",
    why,
  });

const STALE_MS = 30 * 24 * 60 * 60 * 1000;
// HyperFrames phones home and checks for updates unless told not to.
const quietEnv = {
  ...process.env,
  HYPERFRAMES_NO_TELEMETRY: "1",
  DO_NOT_TRACK: "1",
  HYPERFRAMES_NO_UPDATE_CHECK: "1",
};

// A model row's size is its files'; a uv row's, its environment's and its
// checkpoints'.
const filesSize = (r) => r.files?.reduce((n, f) => n + f.size, 0);

// A row with a CPU cost (ACE-Step, own voice) runs on the device torchDevice
// picks; on the CPU, a machine with less RAM than the cost names is refused
// before download.
const cap = rows.some((r) => r.cpu) ? await backend.computeCapability() : null;
const device = (r) => (r.cpu ? torchDevice(cap) : undefined);
const shortOfRam = (r) => device(r) === "cpu" && backend.memory() < r.cpu.ram;
// A uv env's size is the CPU-only pin's, where the row has one and runs on the CPU.
const size = (r) =>
  r.kind === "uv"
    ? (cpuEnv(r, device(r))?.size ?? r.size) + filesSize(r)
    : (r.size ?? filesSize(r));
const installDir = (r) => dest(r, undefined, device(r));
// The OS, CPU and macOS version a row's `unavailable` entries match.
const machine = backend.platform();
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
  if (r.kind === "profile") return `refused: ${r.why}`;
  if (r.kind === "font" && fontGap(r)) return "missing";
  const s = stamp(installDir(r));
  if (!fs.existsSync(s)) {
    // No wheels here: refused before download, since its uv sync could only fail.
    const why = unavailable(r.id, machine);
    if (why) return `refused: ${why}`;
    if (shortOfRam(r))
      return `refused: the CPU path needs ${formatSize(r.cpu.ram)} RAM, this machine has ${formatSize(backend.memory())}`;
    // uv syncs the row's env, so without it the download would end in a failed row.
    if (r.kind === "uv" && !backend.which("uv"))
      return "refused: install uv first, then check again";
    return "missing";
  }
  const now = new Date();
  fs.utimesSync(s, now, now);
  return "present";
}

// Installs in the tool cache for another lock hash, whose stamp no run has
// touched in 30 days. One with no stamp never finished, and ages by its folder.
function stale() {
  const out = [];
  for (const folder of Object.values(TOOL_DIRS)) {
    const base = path.join(dirs.cache, folder);
    for (const name of fs.existsSync(base) ? fs.readdirSync(base).sort() : []) {
      const dir = path.join(base, name);
      const st =
        fs.statSync(stamp(dir), { throwIfNoEntry: false }) ?? fs.statSync(dir);
      const age = Date.now() - st.mtimeMs;
      if (name !== lockHash && age > STALE_MS)
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
// sha256, as ADR 0017 hosts models. Hashed as a stream: a checkpoint can pass
// the 2 GiB a file read takes.
async function fetchFiles(r, dir) {
  for (const f of r.files) {
    const file = path.join(dir, ...f.path.split("/"));
    fs.mkdirSync(path.dirname(file), { recursive: true });
    await backend.download(
      `https://huggingface.co/${r.repo}/resolve/${r.revision}/${f.path}`,
      file,
    );
    const hash = crypto.createHash("sha256");
    for await (const chunk of fs.createReadStream(file)) hash.update(chunk);
    const sum = hash.digest("hex");
    if (sum !== f.sha256)
      throw new Error(`${f.path} has sha256 ${sum}, pinned ${f.sha256}`);
  }
}

async function install(r) {
  if (r.kind === "font") return installFont(r, backend);
  const dir = installDir(r);
  // A missing row's folder can hold what an earlier install left half done.
  // A model is written beside it and renamed in, so it never is.
  if (r.kind !== "model") {
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
  }
  if (r.kind === "npm") {
    for (const f of ["package.json", "package-lock.json"])
      fs.copyFileSync(path.join(skill, f), path.join(dir, f));
    // onnxruntime-node's postinstall otherwise fetches the CUDA 12 provider from
    // NuGet on Linux x64 (1.30.0): a download no row lists.
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
  } else if (r.kind === "model") {
    await staged(dir, (part) => fetchFiles(r, part));
  } else if (r.kind === "uv") {
    // The code at its pinned commit (or, for a row the skill carries, its
    // project folder's pyproject and lock), synced from its own lockfile into a
    // .venv beside it. Filled in place, not staged: the venv records its
    // absolute path.
    if (r.source.path) {
      fs.mkdirSync(path.join(dir, "src"));
      for (const f of ["pyproject.toml", "uv.lock"])
        fs.copyFileSync(
          path.join(skill, r.source.path, f),
          path.join(dir, "src", f),
        );
    } else {
      const zip = path.join(dir, "source.zip");
      await backend.download(
        `https://codeload.github.com/${r.source.repo}/zip/${r.source.revision}`,
        zip,
      );
      await backend.extract(zip, path.join(dir, "src"));
      fs.rmSync(zip);
      // On the CPU, the skill's own pin replaces the upstream's CUDA one.
      const pin = cpuEnv(r, device(r));
      if (pin)
        for (const f of ["pyproject.toml", "uv.lock"])
          fs.copyFileSync(
            path.join(skill, pin.path, f),
            path.join(dir, "src", f),
          );
    }
    const code = await backend.uvSync(path.join(dir, "src"));
    if (code !== 0) throw new Error(`uv sync exited ${code}`);
    await fetchFiles(r, path.join(dir, "checkpoints"));
  }
  fs.writeFileSync(stamp(dir), "");
  return "present";
}

const formatSize = (n) =>
  n >= 1e9
    ? `${(n / 1e9).toFixed(1)} GB`
    : n >= 1e6
      ? `${Math.round(n / 1e6)} MB`
      : `${Math.max(1, Math.round(n / 1e3))} KB`;

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

function report(state, staleInstalls) {
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
          : r.kind === "profile"
            ? "nothing, fix the file"
            : installDir(r);
    lines.push(
      `| ${r.id} | ${r.neededBy} | ${state.get(r)} | ${size(r) ? formatSize(size(r)) : "-"} | ${r.licence} | ${where} |`,
    );
  }
  for (const s of staleInstalls)
    lines.push(
      `| ${s.id} | nothing | stale, unused ${s.days} days | ${formatSize(s.size)} | - | ${s.dir} |`,
    );
  for (const r of rows.filter((r) => r.cpu)) {
    const s = r.cpu.seconds;
    lines.push(
      "",
      torchDevice(cap) === "cuda"
        ? `${r.id} runs on the GPU here (compute capability ${cap.toFixed(1)}).`
        : `${r.id} runs on the CPU here (${cap ? `compute capability ${cap.toFixed(1)}, under 8.0${r.cpu.why ? `: ${r.cpu.why}` : ""}` : "no NVIDIA card"}): about ${Math.floor(s / 60)} min ${s % 60} s and ${formatSize(r.cpu.ram)} RAM per 30 s of ${r.cpu.of}.`,
    );
  }
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
process.exit(report(state, stale()));
