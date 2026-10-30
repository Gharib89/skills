// Shared fixtures of the timing, render and hf tests: a voiced run folder on a
// temp machine whose tool cache holds a stamped npm row, and the runner of a
// stage script under the canned backend.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { lockHash } from "../../skills/creative-video/scripts/lib/tools.mjs";
import { fixture, here, run as voice } from "./voice-lib.mjs";

const scripts = path.join(
  here,
  "..",
  "..",
  "skills",
  "creative-video",
  "scripts",
);
export const timing = path.join(scripts, "render", "timing.mjs");
export const render = path.join(scripts, "render", "render.mjs");
export const hf = path.join(scripts, "hf.mjs");

// A run folder with its voice stage done and the npm row installed, unattended
// (its recorded direction lets the render go ahead without a board).
export function voiced(scenes, language) {
  const fx = fixture(scenes, language);
  fs.writeFileSync(
    path.join(fx.dir, "unattended.json"),
    JSON.stringify({ direction: "switch" }),
  );
  // An Arabic script is voiced by a Gemini narrator, which needs a key.
  const v = voice(fx, language === "ar" ? { GEMINI_API_KEY: "test-key" } : {});
  if (v.code !== 0) throw new Error(`voice stage failed: ${v.out}${v.err}`);
  install(fx);
  if (language === "ar") {
    // The font store's caption face, which timing copies into the project.
    const face = path.join(
      fx.tmp,
      "home",
      ".local",
      "share",
      "creative-video",
      "fonts",
      "ibm-plex-sans-arabic@5.3.0",
    );
    fs.mkdirSync(face, { recursive: true });
    for (const f of ["arabic-400-normal.woff2", "arabic-600-normal.woff2"])
      fs.writeFileSync(path.join(face, f), "wOF2");
    fs.writeFileSync(path.join(face, ".stamp"), "");
  }
  return fx;
}

// The npm row's stamp and the GSAP bundle timing copies from it.
export function install(fx) {
  const node = path.join(fx.tmp, "cache", "creative-video", "node", lockHash);
  fs.mkdirSync(path.join(node, "node_modules", "gsap", "dist"), {
    recursive: true,
  });
  fs.writeFileSync(path.join(node, ".stamp"), "");
  fs.writeFileSync(
    path.join(node, "node_modules", "gsap", "dist", "gsap.min.js"),
    "/* gsap */",
  );
}

export function exec(script, fx, args = [fx.dir], extra = {}) {
  const r = spawnSync(process.execPath, [script, ...args], {
    env: {
      ...extra,
      PATH: process.env.PATH,
      HOME: path.join(fx.tmp, "home"),
      XDG_CACHE_HOME: path.join(fx.tmp, "cache"),
      XDG_VIDEOS_DIR: path.join(fx.tmp, "videos"),
      CREATIVE_VIDEO_BACKEND: path.join(here, "fake-backend.mjs"),
      CREATIVE_VIDEO_FAKE_LOG: fx.log,
    },
    encoding: "utf8",
    timeout: 60000,
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

export const project = (fx, ...p) => path.join(fx.dir, "project", ...p);
export const read = (f) => fs.readFileSync(f, "utf8");
export const readJson = (f) => JSON.parse(read(f));

// Each file in the run's out/ by name, its bytes as base64.
export function outFiles(fx) {
  const out = path.join(fx.dir, "out");
  return Object.fromEntries(
    fs
      .readdirSync(out)
      .map((f) => [f, fs.readFileSync(path.join(out, f)).toString("base64")]),
  );
}

// Writes `compositions/<id>.html` for each scene id, as the agent would.
export function author(fx, ids) {
  fs.mkdirSync(project(fx, "compositions"), { recursive: true });
  for (const id of ids)
    fs.writeFileSync(
      project(fx, "compositions", `${id}.html`),
      `<!-- ${id} -->`,
    );
}

export const calls = (fx) =>
  fs.existsSync(fx.log)
    ? read(fx.log)
        .trim()
        .split("\n")
        .map((l) => JSON.parse(l))
    : [];
