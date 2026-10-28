// The real backend's fetches against a stubbed global fetch: a download whose
// stream dies leaves no file, and an Openverse answer with no results is none.
import { afterEach, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { download } from "../../skills/creative-video/scripts/lib/backend/media.mjs";
import { openverse } from "../../skills/creative-video/scripts/lib/backend/sound.mjs";

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

test("a download whose stream dies mid-file throws and leaves no file at its path", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-download-"));
  try {
    globalThis.fetch = async () =>
      new Response(
        new ReadableStream({
          start(c) {
            c.enqueue(new Uint8Array(64));
            c.error(new Error("connection reset"));
          },
        }),
      );
    const file = path.join(dir, "tear-1.mp3");
    await assert.rejects(download("https://cdn.example/tear-1.mp3", file), {
      message: "connection reset",
    });
    assert.ok(!fs.existsSync(file), "a truncated file is at the path");
  } finally {
    fs.rmSync(dir, { recursive: true });
  }
});

test("a whole download lands at its path", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "creative-download-"));
  try {
    globalThis.fetch = async () => new Response("sound");
    const file = path.join(dir, "tear-1.mp3");
    await download("https://cdn.example/tear-1.mp3", file);
    assert.equal(fs.readFileSync(file, "utf8"), "sound");
    assert.deepEqual(fs.readdirSync(dir), ["tear-1.mp3"]);
  } finally {
    fs.rmSync(dir, { recursive: true });
  }
});

test("an Openverse answer with no results list is no result", async () => {
  globalThis.fetch = async () => new Response("{}");
  assert.deepEqual(await openverse("paper tear", { medium: false }), []);
});
