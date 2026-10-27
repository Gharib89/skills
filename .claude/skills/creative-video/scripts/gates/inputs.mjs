// What a gates record is of, defined once so the gates stage that writes it and
// the render that reads it cannot drift apart.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const hex = (h) => h.digest("hex").slice(0, 16);

// The script a record is of: each scene's id and narration. A pass or a changed
// script starts the fix-attempt count again.
export const scriptHash = (script) =>
  hex(
    crypto
      .createHash("sha256")
      .update(JSON.stringify(script.scenes.map((s) => [s.id, s.narration]))),
  );

// The files under `dir`, through symlinks to files and folders, since the
// project loads what a link points at; a folder seen before is walked once, so
// a link loop ends.
function walk(dir, seen = new Set()) {
  const real = fs.realpathSync(dir);
  if (seen.has(real)) return [];
  seen.add(real);
  return fs.readdirSync(dir).flatMap((name) => {
    const f = path.join(dir, name);
    const stat = fs.statSync(f, { throwIfNoEntry: false });
    if (stat?.isDirectory()) return walk(f, seen);
    return stat?.isFile() ? [f] : [];
  });
}

// Everything a video is rendered from: the timeline, the script, the brief and
// every file of the project but the CLI's own state. A render of other inputs
// than the gates passed is refused.
export function inputsHash(run) {
  const h = crypto.createHash("sha256");
  const files = ["timeline.json", "script.json", "brief.json"]
    .filter((f) => fs.existsSync(path.join(run, f)))
    .map((f) => path.join(run, f));
  const proj = path.join(run, "project");
  files.push(
    ...walk(proj)
      .filter(
        (f) => path.relative(proj, f).split(path.sep)[0] !== ".hyperframes",
      )
      .sort(),
  );
  for (const f of files)
    h.update(path.relative(run, f)).update("\0").update(fs.readFileSync(f));
  return hex(h);
}
