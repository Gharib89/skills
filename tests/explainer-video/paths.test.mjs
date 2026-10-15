// The per-user directories on each OS, the OS injected (ADR 0014, ADR 0017).
import { after, test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  userDirs,
  videosDir,
} from "../../skills/explainer-video/scripts/lib/paths.mjs";

test("Linux follows XDG, falling back to ~/.config, ~/.local/share and ~/.cache", () => {
  assert.deepEqual(userDirs({ platform: "linux", env: {}, home: "/home/u" }), {
    config: "/home/u/.config/explainer-video",
    data: "/home/u/.local/share/explainer-video",
    cache: "/home/u/.cache/explainer-video",
  });
  assert.deepEqual(
    userDirs({
      platform: "linux",
      env: {
        XDG_CONFIG_HOME: "/x/c",
        XDG_DATA_HOME: "/x/d",
        XDG_CACHE_HOME: "/x/k",
      },
      home: "/home/u",
    }),
    {
      config: "/x/c/explainer-video",
      data: "/x/d/explainer-video",
      cache: "/x/k/explainer-video",
    },
  );
});

test("Linux ignores a relative XDG path, as the XDG spec says", () => {
  assert.equal(
    userDirs({
      platform: "linux",
      env: { XDG_CACHE_HOME: "rel" },
      home: "/home/u",
    }).cache,
    "/home/u/.cache/explainer-video",
  );
});

test("macOS uses Application Support and Caches, and ignores XDG", () => {
  assert.deepEqual(
    userDirs({
      platform: "darwin",
      env: { XDG_CACHE_HOME: "/x/k" },
      home: "/Users/u",
    }),
    {
      config: "/Users/u/Library/Application Support/explainer-video",
      data: "/Users/u/Library/Application Support/explainer-video",
      cache: "/Users/u/Library/Caches/explainer-video",
    },
  );
});

test("Windows uses APPDATA for config and LOCALAPPDATA for data and cache, with backslashes", () => {
  assert.deepEqual(
    userDirs({
      platform: "win32",
      env: {
        APPDATA: "C:\\Users\\u\\AppData\\Roaming",
        LOCALAPPDATA: "C:\\Users\\u\\AppData\\Local",
      },
      home: "C:\\Users\\u",
    }),
    {
      config: "C:\\Users\\u\\AppData\\Roaming\\explainer-video",
      data: "C:\\Users\\u\\AppData\\Local\\explainer-video",
      cache: "C:\\Users\\u\\AppData\\Local\\explainer-video",
    },
  );
  assert.equal(
    userDirs({ platform: "win32", env: {}, home: "C:\\Users\\u" }).config,
    "C:\\Users\\u\\AppData\\Roaming\\explainer-video",
  );
});

// The videos folder delivery copies into, read against a temp home.
function home() {
  const h = fs.mkdtempSync(path.join(os.tmpdir(), "explainer-home-"));
  after(() => fs.rmSync(h, { recursive: true, force: true }));
  return h;
}

test("Linux takes an absolute XDG_VIDEOS_DIR, else user-dirs.dirs with $HOME expanded, else ~/Videos", () => {
  const h = home();
  assert.equal(
    videosDir({ platform: "linux", env: { XDG_VIDEOS_DIR: "/v" }, home: h }),
    "/v",
  );
  assert.equal(
    videosDir({ platform: "linux", env: {}, home: h }),
    path.join(h, "Videos"),
  );
  fs.mkdirSync(path.join(h, ".config"));
  fs.writeFileSync(
    path.join(h, ".config", "user-dirs.dirs"),
    '# written by xdg-user-dirs-update\nXDG_DESKTOP_DIR="$HOME/Desktop"\nXDG_VIDEOS_DIR="$HOME/Clips"\n',
  );
  assert.equal(
    videosDir({ platform: "linux", env: {}, home: h }),
    path.join(h, "Clips"),
  );
  const config = path.join(h, "elsewhere");
  fs.mkdirSync(config);
  fs.writeFileSync(
    path.join(config, "user-dirs.dirs"),
    'XDG_VIDEOS_DIR="/media/films"\n',
  );
  assert.equal(
    videosDir({ platform: "linux", env: { XDG_CONFIG_HOME: config }, home: h }),
    "/media/films",
  );
});

test("Linux ignores a relative XDG_VIDEOS_DIR and reads user-dirs.dirs instead", () => {
  const h = home();
  fs.mkdirSync(path.join(h, ".config"));
  fs.writeFileSync(
    path.join(h, ".config", "user-dirs.dirs"),
    'XDG_VIDEOS_DIR="$HOME/Clips"\n',
  );
  assert.equal(
    videosDir({ platform: "linux", env: { XDG_VIDEOS_DIR: "rel" }, home: h }),
    path.join(h, "Clips"),
  );
});

test("macOS delivers to ~/Movies and Windows to <home>\\Videos", () => {
  assert.equal(
    videosDir({
      platform: "darwin",
      env: { XDG_VIDEOS_DIR: "/v" },
      home: "/Users/u",
    }),
    "/Users/u/Movies",
  );
  assert.equal(
    videosDir({ platform: "win32", env: {}, home: "C:\\Users\\u" }),
    "C:\\Users\\u\\Videos",
  );
});
