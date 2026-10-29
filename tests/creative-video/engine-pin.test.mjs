// The engine pin: the hyperframes skill this repo composes (skills-lock.json's
// `hyperframes` ref) and the HyperFrames CLI creative-video installs
// (package.json and its lockfile) are the same release, so the skill's prose
// describes the engine that renders.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// The CLI version each measured lock ref carries. An entry is measured with
// `gh api 'repos/heygen-com/hyperframes/contents/packages/cli/package.json?ref=<ref>'`,
// its `version` (the unscoped npm `hyperframes` package). A lock bump with no
// entry here fails on purpose: measure the new ref, add it, and pin
// package.json to its version.
const ENGINE = {
  "9ebc1f8a13fc2c6756f92394688e35f9891eb5c8": "0.8.206",
  "6df754fbf3289ee0dc19e123e0628cc69218e518": "0.8.216",
};

const root = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
);
const read = (...p) =>
  JSON.parse(fs.readFileSync(path.join(root, ...p), "utf8"));
const shipped = () => ({
  lock: read("skills-lock.json"),
  pkg: read("skills", "creative-video", "package.json"),
  pkgLock: read("skills", "creative-video", "package-lock.json"),
});

// The disagreement between the three files, or null.
function check(lock, pkg, pkgLock) {
  const ref = lock.skills?.hyperframes?.ref;
  const media = lock.skills?.["media-use"]?.ref;
  if (media !== ref)
    return `media-use is locked at ${media}, hyperframes at ${ref}`;
  const want = ENGINE[ref];
  if (!want) return `no measured engine version for the hyperframes ref ${ref}`;
  const pinned = pkg.dependencies?.hyperframes;
  if (pinned !== want)
    return `package.json pins hyperframes ${pinned}, the ref ${ref} carries ${want}`;
  const resolved = pkgLock.packages?.["node_modules/hyperframes"]?.version;
  if (resolved !== want)
    return `package-lock.json resolves hyperframes ${resolved}, package.json pins ${want}`;
  return null;
}

test("the shipped lock, package.json and lockfile agree on the engine", () => {
  const s = shipped();
  assert.equal(check(s.lock, s.pkg, s.pkgLock), null);
});

test("a lock whose hyperframes ref has no measured entry fails", () => {
  const s = shipped();
  s.lock.skills.hyperframes.ref = "0".repeat(40);
  s.lock.skills["media-use"].ref = "0".repeat(40);
  assert.match(
    check(s.lock, s.pkg, s.pkgLock),
    /no measured engine version for the hyperframes ref 0{40}/,
  );
});

test("a media-use lock ref apart from the hyperframes ref fails", () => {
  const s = shipped();
  s.lock.skills["media-use"].ref = "0".repeat(40);
  assert.match(
    check(s.lock, s.pkg, s.pkgLock),
    /media-use is locked at 0{40}, hyperframes at 6df754f/,
  );
});

test("a package.json pinning another version, or a caret range, fails", () => {
  for (const v of ["0.8.217", "^0.8.216"]) {
    const s = shipped();
    s.pkg.dependencies.hyperframes = v;
    assert.equal(
      check(s.lock, s.pkg, s.pkgLock),
      `package.json pins hyperframes ${v}, the ref 6df754fbf3289ee0dc19e123e0628cc69218e518 carries 0.8.216`,
    );
  }
});

test("a lockfile resolving another version fails", () => {
  const s = shipped();
  s.pkgLock.packages["node_modules/hyperframes"].version = "0.8.217";
  assert.match(
    check(s.lock, s.pkg, s.pkgLock),
    /package-lock\.json resolves hyperframes 0\.8\.217/,
  );
});
