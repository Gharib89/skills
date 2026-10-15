// Everything setup reaches outside the machine or the skill: npm, HyperFrames'
// Chrome download, the Fontsource API and CDN, and PATH. EXPLAINER_VIDEO_BACKEND
// names a module with these same exports to use instead, which is how tests
// select canned fakes.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
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
