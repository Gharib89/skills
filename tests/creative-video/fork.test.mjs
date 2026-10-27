// creative-video is a fork of explainer-video's plumbing that stands alone: no
// file reaches into explainer-video, the grammar it left behind stays out, and
// its stores are its own.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { userDirs } from "../../skills/creative-video/scripts/lib/paths.mjs";

const skill = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "skills",
  "creative-video",
);

const files = (dir) =>
  fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.name !== "node_modules")
    .flatMap((e) =>
      e.isDirectory()
        ? files(path.join(dir, e.name))
        : [path.join(dir, e.name)],
    );

test("no file in the skill imports, spawns or names a path into explainer-video", () => {
  const hits = files(skill).flatMap((f) =>
    fs
      .readFileSync(f, "utf8")
      .split("\n")
      .flatMap((l, i) =>
        /explainer-video\/|\.\.\/explainer-video|EXPLAINER_VIDEO_/.test(l)
          ? [`${path.relative(skill, f)}:${i + 1}: ${l.trim()}`]
          : [],
      ),
  );
  assert.deepEqual(hits, []);
});

test("none of the parts left behind exists in the fork, and setup lists no own-voice or ace-step row", () => {
  const left = [
    "scripts/render/compose.mjs",
    "scripts/render/components.mjs",
    "scripts/render/render.mjs",
    "scripts/style",
    "scripts/storyboard",
    "storyboard",
    "scripts/script",
    "scripts/brief",
    "scripts/score",
    "scripts/parts",
    "scripts/voice/own-voice.mjs",
    "scripts/voice/vc",
    "setup/ace-step-cpu",
    "styles",
    "reference/own-voice.md",
    "reference/parts.md",
  ];
  assert.deepEqual(
    left.filter((p) => fs.existsSync(path.join(skill, p))),
    [],
  );
  const { rows } = JSON.parse(
    fs.readFileSync(path.join(skill, "setup", "rows.json"), "utf8"),
  );
  assert.deepEqual(
    rows
      .map((r) => r.id)
      .filter((id) => ["own-voice", "ace-step"].includes(id)),
    [],
  );
});

test("the skill's config, data and tool cache are creative-video's own on every OS", () => {
  for (const platform of ["linux", "darwin", "win32"])
    for (const [kind, dir] of Object.entries(
      userDirs({ platform, env: {}, home: "/home/u" }),
    ))
      assert.equal(
        path.basename(dir.replaceAll("\\", "/")),
        "creative-video",
        `${platform} ${kind}: ${dir}`,
      );
});
