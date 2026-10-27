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

// CREATIVE_VIDEO_BACKEND names a module with the real backend's exports to use
// instead, which is how tests select canned fakes.
export function loadBackend() {
  const override = process.env.CREATIVE_VIDEO_BACKEND;
  return import(
    override ? pathToFileURL(path.resolve(override)).href : "./backend.mjs"
  );
}

// The tool cache's folder per row kind, each holding one install per lock hash.
export const TOOL_DIRS = { npm: "node", chrome: "chrome", cuda: "onnx-cuda" };

// A font by family and version in the font store; a model by its pinned
// revision; npm packages and Chrome by the lockfile's hash.
export function dest(r, dirs = userDirs()) {
  if (r.kind === "font")
    return path.join(dirs.data, "fonts", `${r.family}@${r.version}`);
  if (r.kind === "model")
    return path.join(
      dirs.cache,
      "models",
      `${r.id.replace(/^model:/, "")}@${r.revision.slice(0, 12)}`,
    );
  return path.join(dirs.cache, TOOL_DIRS[r.kind], lockHash);
}

// onnxruntime-node loads its CUDA provider from the folder holding its own
// library, so setup installs the provider's files there. CUDA 13 dropped cards
// under compute capability 7.5, the oldest measured working.
export const ORT_CUDA_LIBS = [
  "libonnxruntime_providers_cuda.so",
  "libonnxruntime_providers_shared.so",
];
export const ORT_CUDA_MIN_CAP = 7.5;
export const ortBin = (node) =>
  path.join(node, "node_modules/onnxruntime-node/bin/napi-v6/linux/x64");

// Whether setup's CUDA provider sits in that npm folder: its stamp lives apart,
// so a rebuilt npm folder leaves the stamp standing without the libraries.
export const ortProvider = (node) =>
  ORT_CUDA_LIBS.every((f) => fs.existsSync(path.join(ortBin(node), f)));

// The licences a font must carry for setup to install it.
export const LICENCES = ["OFL-1.1", "Apache-2.0"];

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

// What a backend loads from: the npm install and each model's folder by id.
export function toolPaths(dirs = userDirs()) {
  return {
    node: dest({ kind: "npm" }, dirs),
    models: Object.fromEntries(
      catalogue()
        .filter((r) => r.kind === "model")
        .map((r) => [r.id, dest(r, dirs)]),
    ),
  };
}
