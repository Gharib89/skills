// The real backend's page reader up to its Chrome launch, in the environment
// snapshot.mjs hands it: a stub puppeteer-core in the tool cache refuses the
// launch with the Chrome path it was handed.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  hyperframesEnv,
  toolPaths,
} from "../../skills/creative-video/scripts/lib/tools.mjs";
import { fixture, write } from "./source-lib.mjs";

test("the real page reader hands puppeteer the Chrome under HyperFrames' home", async () => {
  const fx = fixture({ tools: false });
  const real = process.env.XDG_CACHE_HOME;
  process.env.XDG_CACHE_HOME = fx.env.XDG_CACHE_HOME;
  try {
    const env = hyperframesEnv();
    // HyperFrames' own layout under its home, where setup leaves Chrome.
    const chrome = path.join(env.HOME, ".cache", "hyperframes", "chrome");
    fs.mkdirSync(chrome, { recursive: true });
    fs.writeFileSync(path.join(chrome, "chrome"), "");
    const stub = path.join(toolPaths().node, "node_modules", "puppeteer-core");
    fs.mkdirSync(stub, { recursive: true });
    fs.writeFileSync(
      path.join(stub, "index.js"),
      "exports.launch = async (o) => { throw new Error(`launch ${o.executablePath}`); };",
    );
    const { renderPage } =
      await import("../../skills/creative-video/scripts/lib/backend.mjs");
    const page = pathToFileURL(write(fx, "kit.html", "<p>Hi.</p>")).href;
    await assert.rejects(renderPage(page, { env }), {
      message: `launch ${path.join(chrome, "chrome")}`,
    });
  } finally {
    if (real === undefined) delete process.env.XDG_CACHE_HOME;
    else process.env.XDG_CACHE_HOME = real;
  }
});
