// real-render.mjs renders through a headless shell wrapped with raster flags
// (#917): under load the screenshot route's anti-aliased edge pixels differ
// between renders unless raster is held to one thread, with no partial raster.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  RASTER_FLAGS,
  headlessShell,
  shellWith,
} from "../../skills/explainer-video/maintainer/real-render-shell.mjs";

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), "shell-test-"));

test("the wrapper runs the real shell with the launch's own arguments first and the flags after them", () => {
  const dir = tmp();
  const real = path.join(dir, "real");
  fs.writeFileSync(real, '#!/bin/sh\nprintf "%s\\n" "$@"\n', { mode: 0o755 });
  const wrapper = shellWith(dir, ["--x=1", "--y"], real);
  const out = spawnSync(wrapper, ["--a", "b c"], { encoding: "utf8" });
  assert.equal(out.status, 0);
  assert.deepEqual(out.stdout.split("\n").filter(Boolean), [
    "--a",
    "b c",
    "--x=1",
    "--y",
  ]);
});

test("the raster flags are the five the arms measured", () => {
  assert.deepEqual(RASTER_FLAGS, [
    "--num-raster-threads=1",
    "--disable-partial-raster",
    "--disable-zero-copy",
    "--disable-checker-imaging",
    "--disable-threaded-animation",
  ]);
});

const cached = (home, version) => {
  const bin = path.join(
    home,
    `.cache/hyperframes/chrome/chrome-headless-shell/${version}/chrome-headless-shell-linux64/chrome-headless-shell`,
  );
  fs.mkdirSync(path.dirname(bin), { recursive: true });
  fs.writeFileSync(bin, "ELF");
  return bin;
};

test("the headless shell is found under HyperFrames' cache in the tools home", () => {
  const home = tmp();
  const bin = cached(home, "linux-1.2.3");
  assert.equal(headlessShell(home), bin);
  assert.throws(() => headlessShell(tmp()), /headless shell/);
});

test("of two cached versions, the newest is the one wrapped", () => {
  const home = tmp();
  cached(home, "linux-9.0.1");
  const newest = cached(home, "linux-10.0.1");
  assert.equal(headlessShell(home), newest);
});
