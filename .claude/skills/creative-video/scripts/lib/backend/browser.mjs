// The backend's toolchain: npm and HyperFrames' Chrome.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { quiet, win } from "./common.mjs";

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

export function findChrome(home) {
  const root = path.join(home, ".cache", "hyperframes", "chrome");
  const stack = [root];
  while (stack.length) {
    for (const e of fs.readdirSync(stack.pop(), { withFileTypes: true })) {
      const f = path.join(e.parentPath, e.name);
      if (e.isDirectory()) stack.push(f);
      else if (/^chrome(-headless-shell)?(\.exe)?$/.test(e.name)) return f;
    }
  }
  throw new Error(`no Chrome under ${root}`);
}
