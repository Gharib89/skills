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
    ...fs
      .readdirSync(proj, { recursive: true, withFileTypes: true })
      .filter((e) => e.isFile())
      .map((e) => path.join(e.parentPath, e.name))
      .filter(
        (f) => path.relative(proj, f).split(path.sep)[0] !== ".hyperframes",
      )
      .sort(),
  );
  for (const f of files)
    h.update(path.relative(run, f)).update("\0").update(fs.readFileSync(f));
  return hex(h);
}
