// Maintainer only: how real-render.mjs's determinism row reads two more renders
// against the first, and what a failing row keeps.
import fs from "node:fs";
import path from "node:path";

// For each of `others`, the frame hashes against `a`'s: `at`, the indexes of
// `a`'s frames the other render lacks or draws differently, `extra`, the frames
// it has beyond `a`'s last, and `n`, both together.
export const differing = (a, others) =>
  others.map((b) => {
    const at = a.flatMap((l, i) => (l !== b[i] ? [i] : []));
    const extra = Math.max(0, b.length - a.length);
    return { n: at.length + extra, at, extra };
  });

// The row's detail: each render's count, with the first and last differing
// frame and the frames beyond the first's last where there are any.
export const describe = (diffs) =>
  diffs
    .map(({ n, at, extra }) =>
      n
        ? `${n} (${[
            at.length ? `frames ${at[0]} to ${at.at(-1)}` : "",
            extra ? `${extra} beyond the first's last` : "",
          ]
            .filter(Boolean)
            .join(", ")})`
        : "0",
    )
    .join(" and ");

// Writes each render's frame hashes, `{ name: [hash...] }`, to
// `<dir>/real-render-determinism-<name>.framemd5` (`dir` made if need be);
// returns the paths.
export function keepHashLists(lists, dir) {
  fs.mkdirSync(dir, { recursive: true });
  return Object.entries(lists).map(([name, hashes]) => {
    const file = path.join(dir, `real-render-determinism-${name}.framemd5`);
    fs.writeFileSync(file, hashes.join("\n"));
    return file;
  });
}
