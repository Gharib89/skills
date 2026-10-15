// explainer-video's setup: check the tool rows a run needs, and install the
// missing ones after the human's one yes. Tools go to the per-user tool cache,
// keyed by the lockfile's hash, fonts to the font store (ADR 0017).
//
//   node setup.mjs check [--all]     print the table; installs nothing
//   node setup.mjs install [--all]   the yes: install every missing row, prune
//                                    every stale install, print the table again
//
// --all adds the opt-in rows. A system package (ffmpeg, uv) is never installed:
// its install lines (Linux, brew, winget) are printed for the human to run.
// stdout: the table (row, needed by, status, size, licence, writes to), the
//         install lines of each missing system package, one summary line
// exit:   0 every row present, nothing stale · 1 a row missing, refused or
//         failed, or an install stale · 2 usage
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { userDirs } from "./lib/paths.mjs";
import {
  TOOL_DIRS,
  catalogue as readCatalogue,
  dest as destIn,
  lockHash,
  loadBackend,
  skill,
} from "./lib/tools.mjs";

const usage = "usage: node setup.mjs check|install [--all]";
const [mode, ...flags] = process.argv.slice(2);
if (!["check", "install"].includes(mode) || flags.some((f) => f !== "--all")) {
  console.error(usage);
  process.exit(2);
}
const all = flags.includes("--all");

const backend = await loadBackend();
const dirs = userDirs();
const catalogue = readCatalogue();

// Every row without a `when`; opt-in rows under --all; a `when: python` row
// (uv) only beside a row that runs Python.
const rows = catalogue.filter((r) => !r.when || (all && r.when === "opt-in"));
if (rows.some((r) => r.python))
  rows.push(...catalogue.filter((r) => r.when === "python"));

const LICENCES = ["OFL-1.1", "Apache-2.0"];
const STALE_MS = 30 * 24 * 60 * 60 * 1000;
// HyperFrames phones home and checks for updates unless told not to.
const quietEnv = {
  ...process.env,
  HYPERFRAMES_NO_TELEMETRY: "1",
  DO_NOT_TRACK: "1",
  HYPERFRAMES_NO_UPDATE_CHECK: "1",
};

const dest = (r) => destIn(r, dirs);
// A model row's size is its files'.
const size = (r) => r.size ?? r.files?.reduce((n, f) => n + f.size, 0);
const stamp = (dir) => path.join(dir, ".stamp");
const du = (p) => {
  const s = fs.lstatSync(p);
  return s.isDirectory()
    ? fs.readdirSync(p).reduce((n, f) => n + du(path.join(p, f)), 0)
    : s.size;
};

// An install is present once its stamp is written, the last step of its install.
// Checking it touches the stamp, so an install a run still uses never goes stale.
function status(r) {
  if (r.kind === "system")
    return backend.which(r.command) ? "present" : "missing";
  const s = stamp(dest(r));
  if (!fs.existsSync(s)) return "missing";
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

async function install(r) {
  const dir = dest(r);
  // A missing row's folder can hold what an earlier install left half done.
  // A font or a model is written beside it and renamed in, so it never is.
  if (r.kind !== "font" && r.kind !== "model") {
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
  } else if (r.kind === "font") {
    const meta = await backend.fontMeta(r.family);
    if (!LICENCES.includes(meta.license))
      return `refused: licence ${meta.license}, only ${LICENCES.join(" or ")}`;
    const part = `${dir}.part`;
    fs.rmSync(part, { recursive: true, force: true });
    fs.mkdirSync(part, { recursive: true });
    for (const f of r.files) {
      await backend.download(
        `https://cdn.jsdelivr.net/fontsource/fonts/${r.family}@${r.version}/${f}.woff2`,
        path.join(part, `${f}.woff2`),
      );
    }
    fs.rmSync(dir, { recursive: true, force: true });
    fs.renameSync(part, dir);
  } else if (r.kind === "model") {
    // Pinned by revision and checked by sha256, as ADR 0017 hosts models.
    const part = `${dir}.part`;
    fs.rmSync(part, { recursive: true, force: true });
    for (const f of r.files) {
      const file = path.join(part, ...f.path.split("/"));
      fs.mkdirSync(path.dirname(file), { recursive: true });
      await backend.download(
        `https://huggingface.co/${r.repo}/resolve/${r.revision}/${f.path}`,
        file,
      );
      const sum = crypto
        .createHash("sha256")
        .update(fs.readFileSync(file))
        .digest("hex");
      if (sum !== f.sha256)
        throw new Error(`${f.path} has sha256 ${sum}, pinned ${f.sha256}`);
    }
    fs.rmSync(dir, { recursive: true, force: true });
    fs.renameSync(part, dir);
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

function report(state, staleInstalls) {
  const lines = [
    "| row | needed by | status | size | licence | writes to |",
    "| --- | --- | --- | --- | --- | --- |",
  ];
  for (const r of rows) {
    const where = r.kind === "system" ? "system, you install it" : dest(r);
    lines.push(
      `| ${r.id} | ${r.neededBy} | ${state.get(r)} | ${size(r) ? formatSize(size(r)) : "-"} | ${r.licence} | ${where} |`,
    );
  }
  for (const s of staleInstalls)
    lines.push(
      `| ${s.id} | nothing | stale, unused ${s.days} days | ${formatSize(s.size)} | - | ${s.dir} |`,
    );
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
  const missing = rows.filter((r) => state.get(r) !== "present");
  const parts = [];
  // A system package has no size: setup installs none of them.
  const total = missing.reduce((n, r) => n + (size(r) || 0), 0);
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
    if (state.get(r) !== "missing" || r.kind === "system") continue;
    try {
      state.set(r, await install(r));
    } catch (e) {
      state.set(r, `failed: ${e.message}`);
    }
  }
  for (const s of stale()) fs.rmSync(s.dir, { recursive: true, force: true });
}
process.exit(report(state, stale()));
