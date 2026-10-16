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
export const renderInputs = (families) => [
  lockHash,
  ...families.map(
    (f) =>
      `${f}@${catalogue().find((r) => r.kind === "font" && r.family === f)?.version}`,
  ),
];

// What a backend loads from: the npm install, and each model's folder by id.
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
