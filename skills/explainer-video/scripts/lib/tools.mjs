// The setup catalogue and where each row lands (ADR 0017), shared by setup,
// which installs the rows, and the stages that load what it installed.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { userDirs } from "./paths.mjs";

export const skill = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
);

export const catalogue = () =>
  JSON.parse(fs.readFileSync(path.join(skill, "setup", "rows.json"), "utf8"))
    .rows;

export const lockHash = crypto
  .createHash("sha256")
  .update(fs.readFileSync(path.join(skill, "package-lock.json")))
  .digest("hex")
  .slice(0, 16);

// EXPLAINER_VIDEO_BACKEND names a module with the real backend's exports to use
// instead, which is how tests select canned fakes.
export function loadBackend() {
  const override = process.env.EXPLAINER_VIDEO_BACKEND;
  return import(
    override ? pathToFileURL(path.resolve(override)).href : "./backend.mjs"
  );
}

// The tool cache's folder per row kind, each holding one install per lock hash.
export const TOOL_DIRS = { npm: "node", chrome: "chrome" };

// A font by family and version in the font store; a model by its pinned
// revision; a uv row by its code's and its checkpoints' (the code of a row
// that lives in the skill, by the hash of its uv.lock); npm packages and
// Chrome by the lockfile's hash. A uv row with a CPU-only pin (`cpu.env`) on
// the `cpu` device gets a folder of its own, named by that pin's lock hash, so
// an env synced for one device is never the other's.
export function dest(r, dirs = userDirs(), device) {
  if (r.kind === "font")
    return path.join(dirs.data, "fonts", `${r.family}@${r.version}`);
  if (r.kind === "uv") {
    const hashOf = (p) =>
      crypto
        .createHash("sha256")
        .update(fs.readFileSync(path.join(skill, p, "uv.lock")))
        .digest("hex")
        .slice(0, 7);
    const code = r.source.path ? hashOf(r.source.path) : r.source.revision;
    const pin = cpuEnv(r, device);
    return path.join(
      dirs.cache,
      "python",
      `${r.id}@${code.slice(0, 7)}-${r.revision.slice(0, 7)}${pin ? `-cpu${hashOf(pin.path)}` : ""}`,
    );
  }
  if (r.kind === "model")
    return path.join(
      dirs.cache,
      "models",
      `${r.id.replace(/^model:/, "")}@${r.revision.slice(0, 12)}`,
    );
  return path.join(dirs.cache, TOOL_DIRS[r.kind], lockHash);
}

// The torch device ACE-Step and the own voice's conversion run on, for a card's
// compute capability (null with no NVIDIA card): CUDA from 8.0, which has
// bfloat16; under it acestep runs CUDA in float16, which gives NaN, so the CPU.
export const torchDevice = (cap) => (cap >= 8 ? "cuda" : "cpu");

// A row's CPU-only pin (`cpu.env`) where it runs on the `cpu` device, else
// undefined.
export const cpuEnv = (r, device) =>
  device === "cpu" ? r.cpu?.env : undefined;

// Why the catalogue row `id` cannot install on platform `p`
// (backend.platform()), from the first of its `unavailable` entries `p`
// matches: same os, same arch where the entry names one, a version under its
// `below` where it names one (an unknown version never matches). Null where
// nothing matches.
export function unavailable(id, p) {
  const older = (a, b) => {
    const [x, y] = [a, b].map((v) => v.split(".").map(Number));
    for (let k = 0; k < Math.max(x.length, y.length); k++)
      if ((x[k] ?? 0) !== (y[k] ?? 0)) return (x[k] ?? 0) < (y[k] ?? 0);
    return false;
  };
  const hit = catalogue()
    .find((r) => r.id === id)
    ?.unavailable?.find(
      (u) =>
        u.os === p.os &&
        (!u.arch || u.arch === p.arch) &&
        (!u.below || (p.version && older(p.version, u.below))),
    );
  return hit
    ? `unavailable on ${p.os}/${p.arch}${p.version ? ` ${p.version}` : ""}: ${hit.why}`
    : null;
}

// The licences a font must carry for setup to install it or a draft to name it.
export const LICENCES = ["OFL-1.1", "Apache-2.0"];

// A profile's font row by family: the catalogue's, else the one the profile
// carries for a family a draft fetched.
export const fontRow = (profile, family) =>
  catalogue().find((r) => r.kind === "font" && r.family === family) ??
  profile.fonts?.find((r) => r.family === family);

// Why a font row is not usable, or undefined: its stamp (written last) is
// absent, or the folder lacks one of the row's files.
export function fontGap(r) {
  const dir = dest(r);
  if (!fs.existsSync(path.join(dir, ".stamp")))
    return `${r.id} is not installed`;
  const lost = r.files.find(
    (f) => !fs.existsSync(path.join(dir, `${f}.woff2`)),
  );
  return lost && `${r.id} lacks ${lost}.woff2`;
}

// The weights a font row's files hold, each named `<subset>-<weight>-<style>`.
export const weights = (r) => r.files.map((f) => +f.match(/-(\d+)-/)[1]);

// The weight in `ws` nearest `w`.
export const nearest = (w, ws) =>
  ws.reduce((a, b) => (Math.abs(b - w) < Math.abs(a - w) ? b : a));

// Fill `<dir>.part`, then rename it over `dir`, so a failed fill never leaves a
// half-written folder where an install is looked for.
export async function staged(dir, fill) {
  const part = `${dir}.part`;
  fs.rmSync(part, { recursive: true, force: true });
  fs.mkdirSync(part, { recursive: true });
  await fill(part);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.renameSync(part, dir);
}

// A font row's files from Fontsource into the font store, stamped last;
// `present`, or a refusal naming a licence outside LICENCES.
export async function installFont(r, backend) {
  const meta = await backend.fontMeta(r.family);
  if (!meta) throw new Error(`Fontsource has no family ${r.family}`);
  if (!LICENCES.includes(meta.license))
    return `refused: licence ${meta.license}, only ${LICENCES.join(" or ")}`;
  const dir = dest(r);
  await staged(dir, async (part) => {
    for (const f of r.files)
      await backend.download(
        `https://cdn.jsdelivr.net/fontsource/fonts/${r.family}@${r.version}/${f}.woff2`,
        path.join(part, `${f}.woff2`),
      );
  });
  fs.writeFileSync(path.join(dir, ".stamp"), "");
  return "present";
}

// The environment HyperFrames runs in: it finds Chrome under its home folder,
// where setup put it, and keeps its own state files there too.
export function hyperframesEnv() {
  const home = dest({ kind: "chrome" });
  return {
    ...process.env,
    HYPERFRAMES_NO_TELEMETRY: "1",
    DO_NOT_TRACK: "1",
    HYPERFRAMES_NO_UPDATE_CHECK: "1",
    HOME: home,
    USERPROFILE: home,
  };
}

// What draws a frame beyond the composition's own files: the npm install
// (HyperFrames, GSAP) and Chrome by the lock, and each font family's version.
export const renderInputs = (families, profile) => [
  lockHash,
  ...families.map((f) => `${f}@${fontRow(profile, f)?.version}`),
];

// What a backend loads from: the npm install, each model's folder by id, and
// the own-voice row's folder.
export function toolPaths(dirs = userDirs()) {
  const own = catalogue().find((r) => r.id === "own-voice");
  return {
    node: dest({ kind: "npm" }, dirs),
    models: Object.fromEntries(
      catalogue()
        .filter((r) => r.kind === "model")
        .map((r) => [r.id, dest(r, dirs)]),
    ),
    ...(own && { ownVoice: dest(own, dirs) }),
  };
}

// GSAP and each font row's files copied into a composition folder, as
// HyperFrames lint refuses `../` asset paths; returns the faces the page
// declares, `{family, file, weight, style}` each.
export function compositionAssets(fontRows, dir) {
  fs.mkdirSync(path.join(dir, "fonts"), { recursive: true });
  fs.copyFileSync(
    path.join(toolPaths().node, "node_modules", "gsap", "dist", "gsap.min.js"),
    path.join(dir, "gsap.min.js"),
  );
  const fonts = [];
  for (const r of fontRows)
    for (const f of fs
      .readdirSync(dest(r))
      .filter((f) => f.endsWith(".woff2"))
      .sort()) {
      const file = `${r.family}-${f}`;
      fs.copyFileSync(path.join(dest(r), f), path.join(dir, "fonts", file));
      const m = f.match(/-(\d+)-(normal|italic)\.woff2$/);
      fonts.push({
        family: r.family,
        file,
        weight: m?.[1] ?? 400,
        style: m?.[2] ?? "normal",
      });
    }
  return fonts;
}
