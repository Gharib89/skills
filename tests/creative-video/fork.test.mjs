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

// A quote, backtick or separator before or a separator after `explainer-video`
// or its `explainers` run folder, or its environment variable. In Markdown a
// backtick marks code in prose, not a path, so it is left out there; in code a
// backticked name is a template literal, so prose naming it there hits too.
const CODE =
  /["'`/\\](explainer-video|explainers)\b|\b(explainer-video|explainers)[/\\]|EXPLAINER_VIDEO_/;
const MARKDOWN =
  /["'/\\](explainer-video|explainers)\b|\b(explainer-video|explainers)[/\\]|EXPLAINER_VIDEO_/;
const reaches = (file, line) =>
  (file.endsWith(".md") ? MARKDOWN : CODE).test(line);

test("the reach matcher hits every way code names explainer-video's paths, and not unquoted prose", () => {
  for (const l of [
    'import { x } from "../../explainer-video/scripts/lib/paths.mjs";',
    'path.join(skill, "..", "explainer-video", "scripts")',
    '"..\\\\explainer-video\\\\x"',
    "`${root}/../explainer-video`",
    "path.join(dir, `explainer-video`)",
    'path.resolve("explainers")',
    "process.env.EXPLAINER_VIDEO_BACKEND",
  ])
    assert.ok(reaches("x.mjs", l), l);
  assert.ok(reaches("x.md", "Read `../explainer-video/SKILL.md`."));
  assert.ok(reaches("x.md", "Read `explainer-video/SKILL.md`."));
  assert.ok(reaches("x.mjs", "cd explainer-video/scripts"));
  for (const l of [
    "// forked from explainer-video's plumbing",
    "// the explainers stage",
  ])
    assert.ok(!reaches("x.mjs", l), l);
  assert.ok(!reaches("x.md", "A request for an `explainer-video` goes there."));
});

test("no file in the skill imports, spawns or names a path into explainer-video", () => {
  const hits = files(skill).flatMap((f) =>
    fs
      .readFileSync(f, "utf8")
      .split("\n")
      .flatMap((l, i) =>
        reaches(f, l)
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
